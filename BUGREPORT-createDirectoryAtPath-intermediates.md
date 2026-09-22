# BUG: `createDirectoryAtPath:withIntermediateDirectories:YES` stops at the first component that exists, creates nothing after it, and returns `YES`

**Component:** `MulleObjCPosixFoundation` (`-[NSFileManager createDirectoryAtPath:withIntermediateDirectories:attributes:error:]`), with an identical twin in `MulleObjCWindowsFoundation`
**Type:** correctness - the call reports success and leaves the directories absent
**Severity:** high; silent, and the failure surfaces later and elsewhere as "could not write"
**Found in:** `MulleObjCPosixFoundation` as of 2026-09-16
**Also present in:** `MulleObjCWindowsFoundation`, plus the amalgamated / pre-split copies (table below)

---

## Summary

`-createDirectoryAtPath:withIntermediateDirectories:attributes:error:` fails to
create intermediate directories whenever **any** component of the path already
exists. The walk over the path components treats `EEXIST` as "stop" with a
`break`, which leaves the `for` loop altogether instead of moving on to the next
component:

```c
   for( i = 0; i < n; i++)
   {
      [subComponents addObject:[components objectAtIndex:i]];
      subpath = [NSString pathWithComponents:subComponents];

      rc = [self _createDirectoryAtPath:subpath
                             attributes:attributes];
      if( rc == EEXIST)
         break;                       // <-- leaves the loop, not the component

      if( rc)
         return( NO);
      ...
   }

   return( YES);                      // <-- "success", with components missing
```

So the whole creation only works when *every* component is new. The moment the
path has a prefix on disk - which is the normal case, since the destination
directory usually exists - nothing below that prefix is created, and the method
still answers `YES`.

The caller has no way to tell. `fileExistsAtPath:` afterwards is `NO`, and the
next thing that needs the directory fails with an error that points at the file,
not at the directory:

```
2026-09-16-my-first-post.md: could not write "2026/09/16/my-first-post.html"
```

## Affected code

Identical defect in both implementations, and in the copies of them:

| file | line | |
| --- | --- | --- |
| `MulleObjCPosixFoundation/src/NSFileManager+Posix.m` | 284-285 | the implementation |
| `MulleObjCWindowsFoundation/src/NSFileManager+Windows.m` | 325-326 | the twin |
| `MulleFoundation/src/MulleObjCPosixFoundation/NSFileManager+Posix.m` | 284-285 | the copy the *consumers* compile |
| `MulleObjCOSFoundation.borked/src/Posix/NSFileManager+Posix.m` | 284-285 | pre-split (derived) |
| `pre-split/MulleObjCOSFoundation/src/Posix/NSFileManager+Posix.m` | 284-285 | (derived) |

The third row is worth spelling out, because it is the one that produced the
trace below: `lanyon` and the two cmake tools link the outer `MulleFoundation`
amalgamation, and *that* repo carries its own read-only, git-tracked copy of this
file. It has to be refreshed together with the sub-repo, or a fix applied only to
`MulleObjCPosixFoundation` will not reach the projects that hit the bug.

Note also that "the" `MulleObjCOSFoundation` no longer contains this file - after
the split the Posix implementation lives in `MulleObjCPosixFoundation`, which is
where a fix has to go.

## Reproduction

Five calls, made in this order in a directory in which nothing exists yet.
Observed through `lanyon`, which links the framework:

```objc
   NSFileManager   *fileManager;
   NSArray         *probe;
   NSString        *p;

   fileManager = [NSFileManager defaultManager];
   probe       = @[ @"probe2/p/x/y",    // nothing exists yet
                    @"probe2/p/b",      // one level, under an existing one
                    @"probe2/p/c/d",    // two levels, under an existing one
                    @"probe3/p",        // fresh root, one level
                    @"probe3/p/b/c" ];  // root now exists, two levels

   for( p in probe)
      MulleObjCFprintf( stderr, @"PROBE <%@> rval=%d exists=%d/%d\n",
                        p,
                        (int) [fileManager createDirectoryAtPath:p
                                     withIntermediateDirectories:YES
                                                      attributes:nil
                                                           error:NULL],
                        (int) [fileManager fileExistsAtPath:p],
                        (int) [fileManager fileExistsAtPath:[p stringByDeletingLastPathComponent]]);
```

### Observed

```
PROBE <probe2/p/x/y> rval=1 exists=1/1     correct, whole chain was new
PROBE <probe2/p/b> rval=1 exists=1/1       correct, the simple case (see below)
PROBE <probe2/p/c/d> rval=1 exists=0/0     WRONG - yes, and nothing was created
PROBE <probe3/p> rval=1 exists=1/1         correct, root did not exist
PROBE <probe3/p/b/c> rval=1 exists=0/0     WRONG - root now exists
```

The second column of the last two rows is the point: the *parent* is missing too,
so this is not "the last component was already there", it is "the walk stopped".

### Expected

```
PROBE <probe2/p/c/d> rval=1 exists=1/1
PROBE <probe3/p/b/c> rval=1 exists=1/1
```

The statements to test against are two-liners, and they are the ones the API
promises:

* after `-createDirectoryAtPath:x withIntermediateDirectories:YES ...`, either
  `x` is a directory, or the method answered `NO`
* a component that already exists is not an error

## Root cause

`break` inside a `for` loop terminates the loop; it does not behave like the
`break` inside the `switch` the code was evidently modelled on (the comment in
`_createDirectoryAtPath:` says a `switch` was avoided "because of cosmopolitan",
which is very likely where this shape came from). Meanwhile `EEXIST` from a
component is not an error - it is the normal "this level is already there" answer
that the walk is supposed to skip past.

Two details make the method look healthy in the cases people usually try:

1. **The simple case comes first.** `_createDirectoryAtPath:path` is attempted on
   the full path before the walk:

   ```c
   rc = [self _createDirectoryAtPath:path attributes:attributes];
   if( ! rc)
      ...
      return( YES);
   ```

   If the parent exists, a single `mkdir` suffices and the walk is never reached.
   Creating one level below an existing directory - the common case in code and
   in tests - therefore works.

2. **When nothing exists, the walk works.** With `probe2/p/x/y` every component
   is fresh, no `EEXIST` occurs, and all four levels are created. A test that
   creates its whole tree from scratch passes.

The failure needs the two together: an existing prefix **and** more than one
level below it. In that case the walk stops at the existing prefix and creates
none of the rest, because the loop order is prefix-first - the first `EEXIST` is
always the one that ends the walk.

There is a second, smaller defect in the same loop. After creating a component it
does:

```c
      if( ! [self setAttributes:attributes
                   ofItemAtPath:path          // <-- the FULL path, not subpath
                          error:error])
         return( NO);
```

`path` is the path being asked for, which does not exist yet at that point, so
with a non-`nil` `attributes` (a caller passing `NSFilePosixPermissions`, say)
this fails and aborts the walk - even in cases where the walk would otherwise
succeed. It is invisible with `attributes:nil`, which is what the callers in the
tree all pass. The simple case also strips `NSFilePosixPermissions` before
calling `setAttributes:`, and the walk does not.

## Impact

* **Silent, and it looks random to the caller.** `lanyon` (a static site
  generator) writes posts to permalink paths such as
  `2026/09/16/my-first-post.html`. The **first** post of a run created the
  destination root and succeeded; the second one failed, because the root now
  existed. Same code, same pattern, different answer - which is exactly the shape
  of bug that gets worked around instead of reported.
* **The reported error is misleading.** The write fails, so the message names the
  file. Nothing in it suggests the directory was never created, and the failing
  call had already returned `YES`.
* **In-tree callers that escape it only by accident.**
  `MulleFoundation-demo/cmake-flatten/src/main.m:349` and
  `MulleFoundation-demo/cmake-graph/src/main.m:86` both call it with
  `withIntermediateDirectories:YES`, and both got away with it because their
  output path was a single level under an existing directory, or the whole chain
  was new. They would fail on the first run that had a partial tree.
* **The deprecated one-level API is *not* affected**, because it delegates with
  `createIntermediates:NO`:

  ```objc
  - (BOOL) createDirectoryAtPath:(NSString *) path
                      attributes:(NSDictionary *) attributes
  {
     return( [self createDirectoryAtPath:path
             withIntermediateDirectories:NO
                              attributes:attributes
                                   error:NULL]);
  }
  ```

  This is why a caller who creates each level by hand is safe, and it is also why
  the two APIs appear to disagree with each other.

## Suggested fix

One word, in both source files:

```diff
--- a/src/NSFileManager+Posix.m
+++ b/src/NSFileManager+Posix.m
@@ -281,8 +281,8 @@ - (BOOL) createDirectoryAtPath:(NSString *) path
       rc = [self _createDirectoryAtPath:subpath
                              attributes:attributes];
       if( rc == EEXIST)
-         break;
+         continue;

       if( rc)
          return( NO);
```

`continue` is also the correct answer for the case where a *component* exists but
is not a directory: the walk moves on, and the next `mkdir` fails with `ENOTDIR`
(`-1` from `_createDirectoryAtPath:`), so the method returns `NO` where today it
returns `YES` with a path that could never be built. The `path`/`subpath` slip
above is worth fixing at the same time:

```diff
       if( ! [self setAttributes:attributes
-                   ofItemAtPath:path
+                   ofItemAtPath:subpath
                           error:error])
          return( NO);
```

and, for consistency with the simple case, removing the permission bits that
were already applied by the `mkdir`:

```c
      attributes = [attributes mulleDictionaryByRemovingObjectForKey:NSFilePosixPermissions];
```

in the walk, guarded by `if( attributes)`.

Same three changes in
`MulleObjCWindowsFoundation/src/NSFileManager+Windows.m` (the `break` is at line
325 there). That file cannot be exercised from here - it is Windows only - but
the walk is character-for-character the same, so it has the same bug and the same
fix.

## Regression test

The sequence matters and is the whole test; a test that creates a tree from
scratch passes today. Neither project has a `test/` directory yet, so this needs
`mulle-sde test init` in `MulleObjCPosixFoundation` first; after that, in
`MulleObjCPosixFoundation/test/NSFileManager/`:

```c
   [fileManager removeItemAtPath:@"testdir" error:NULL];   // really empty

   // 1. the whole chain is new: passes today, must keep passing
   rval = [fileManager createDirectoryAtPath:@"testdir/a/b/c"
                    withIntermediateDirectories:YES
                                     attributes:nil
                                          error:NULL];
   assert( rval);
   assert( [fileManager fileExistsAtPath:@"testdir/a/b/c"]);

   // 2. two levels below something that exists: FAILS today
   rval = [fileManager createDirectoryAtPath:@"testdir/x/y"
                    withIntermediateDirectories:YES
                                     attributes:nil
                                          error:NULL];
   assert( rval);
   assert( [fileManager fileExistsAtPath:@"testdir/x/y"]);   // the assertion that matters

   // 3. a component that already exists is not an error
   rval = [fileManager createDirectoryAtPath:@"testdir/a/b"
                    withIntermediateDirectories:YES
                                     attributes:nil
                                          error:NULL];
   assert( rval);
```

Case 2 alone is sufficient, and it is deliberately the *second* call in the file:
the bug needs a prefix that is already there.

## Workaround in place

`lanyon` no longer calls the method. It creates its components one at a time
through the single-level API, which delegates with `createIntermediates:NO` and
is unaffected:

```objc
   for( i = 0; i < n; i++)
   {
      component = [components objectAtIndex:i];

      // a leading "/" is the separator itself and not a component to append
      if( [component isEqualToString:@"/"])
         subpath = [subpath stringByAppendingString:component];
      else
         subpath = [subpath stringByAppendingPathComponent:component];

      if( [fileManager fileExistsAtPath:subpath
                            isDirectory:NULL])
         continue;

      [fileManager createDirectoryAtPath:subpath
                              attributes:nil];
      if( ! [fileManager fileExistsAtPath:subpath
                              isDirectory:NULL])
         return( NO);
   }
```

That is the caller doing the framework's job, and it is also the shape the
framework's own walk should have had. It can be removed once the one-word fix
lands - the workaround does not depend on the bug, so leaving it is harmless, but
it should not become the reason nobody fixes this.

## Notes

- Nothing in the tree tests this method with a pre-existing prefix: a search for
  `withIntermediateDirectories:YES` finds callers only in demo/UI projects, none
  of which create a deep tree next to an existing one.
- `-createDirectoryAtPath:withIntermediateDirectories:NO` is *not* affected: with
  the walk unreachable it either makes the directory or answers `NO`, which is
  correct and is why the per-component workaround is reliable.
- `_createDirectoryAtPath:` returns the raw `errno` for `EEXIST`/`ENOENT` and `-1`
  for anything else, so the values 0, `EEXIST`, `ENOENT` and `-1` all have to be
  distinguished by the caller. A comment at that method saying so would save the
  next reader the round trip - the `EEXIST` handling is correct in the "stop the
  walk" sense only if stopping is what one wants, which is almost never.
