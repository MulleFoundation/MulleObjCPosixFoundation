# BUG: on Linux `NSTimeZone` can not read the zoneinfo database — every zone name resolves to GMT, silently

**Component:** the vendored tzcode (`TZDIR` in `private.h`/`tzfile.h`/`localtime.c`) in
`MulleObjCPosixFoundation`, together with `NSTimeZone` in
`MulleObjCStandardFoundation` and its `NSTimeZone( Posix)` category
**Type:** correctness — a wrong answer that looks right; two further defects in the
same class
**Severity:** high; silent, affects every consumer that formats or renders a date
in a named zone, and there is no diagnostic path at all
**Found in:** a build from the umbrella `MulleFoundation` sources as of 2026-09-27,
on Linux, `/etc/localtime -> /usr/share/zoneinfo/Europe/Berlin`, `TZ` unset
**Status:** open
**Filed in:** `MulleObjCPosixFoundation` — see §8 for why not in
`MulleObjCOSFoundation`, where the NSTimeZone tests live

---

## 1. Summary

`NSTimeZone` answers **GMT** for every time zone name on Linux. Not just for
unknown ones — for `Europe/Berlin`, `America/New_York`, all of them:

```
timeZoneWithName:Europe/Berlin     -> name=Europe/Berlin  abbr=GMT  offset=+0   dst=NO
timeZoneWithName:America/New_York  -> name=America/New_York abbr=GMT offset=+0  dst=NO
timeZoneWithName:Asia/Kolkata      -> name=Asia/Kolkata  abbr=GMT  offset=+0   dst=NO
```

The name is preserved, the offset and abbreviation are not, so the object *looks*
misconfigured rather than unresolvable. The cause is one compile-time path:

```
mulle_get_zoneinfo_path() = /usr/local/etc/zoneinfo
$ ls -d /usr/local/etc/zoneinfo
ls: cannot access '/usr/local/etc/zoneinfo': No such file or directory
```

`_TZDIR` is `/usr/local/etc/zoneinfo`, which is the tzcode default from
`tzfile.h`. On Linux the intended override never applies, because `private.h`
guards it:

```c
#ifdef __APPLE__
#define TZDIR  "/usr/share/zoneinfo"
#endif
```

So on every non-Apple platform `tzload()` fails for every relative zone name,
`__tzset()` silently falls through `tzparse()` (which only accepts POSIX `TZ`
strings such as `CET-1CEST,M3.5.0,M10.5.0/3`) to `gmtload()`, and the caller gets
a GMT timezone carrying the name it asked for. The bundled tzfile reader itself
is fine: with an absolute path it reads this host's `TZif2` files correctly.

This is not a host or packaging accident. A correct `TZDIR` is a property of the
build, and nothing in the tree supplies one.

## 2. Proof

Built against `libMulleFoundation.a` from the dependency of `MulleHeizer`, which
compiles the amalgamation copies of these sources. The object that provides the
tzcode still contains the wrong literal and does **not** contain the right one:

```
$ nm -A libMulleFoundation.a | grep 'T mulle_tz_context_with_name'
libMulleFoundation.a:localtime.c.o: T mulle_tz_context_with_name
$ ar p libMulleFoundation.a localtime.c.o | strings | grep zoneinfo
/usr/local/etc/zoneinfo
$ ar p libMulleFoundation.a localtime.c.o | strings | grep '/usr/share/zoneinfo'
   (empty)
```

At the C level, where `tzload` can be told apart from `tzparse`:

```
$ env -u TZ ./tzprobe2
mulle_get_zoneinfo_path()        = /usr/local/etc/zoneinfo
mulle_get_timezone_zone_tab_file() = /usr/local/etc/zoneinfo/zone.tab
tz_context_with_name:
  name=Europe/Berlin                     offset=+0      <-- tzload failed, gmtload
  name=/usr/share/zoneinfo/Europe/Berlin offset=+7200   <-- the reader is fine
  name=/etc/localtime                    offset=+7200   <-- and so is /etc/localtime
  name=America/New_York                  offset=+0
  name=Bogus/Nowhere                     offset=+0
  name=CET-1CEST,M3.5.0,M10.5.0/3        offset=+7200   <-- tzparse path works
libc tzset with TZ=Europe/Berlin: gmtoff=+7200 abbr=CEST isdst=1
```

At the Objective-C level (`env -u TZ`, host is CEST, `+02:00`):

```
defaultTimeZone                    -> name=(nil) abbr=GMT offset=+0
systemTimeZone                     -> name=(nil) abbr=GMT offset=+0
localTimeZone                      -> name=(nil) abbr=(nil) offset=+0
timeZoneWithName:Europe/Berlin     -> name=Europe/Berlin abbr=GMT offset=+0
timeZoneWithName:Bogus/Nowhere     -> name=Bogus/Nowhere abbr=GMT offset=+0
timeZoneWithAbbreviation:CEST      -> name=Europe/Paris abbr=GMT offset=+0
knownTimeZoneNames count           = 0
abbreviationDictionary count       = 48
timeZoneForSecondsFromGMT:7200     -> name=GMT +0200 abbr=GMT +0200 offset=+7200
calendarDateWithTimeZone:Europe/Berlin -> 2026-09-27T20:47Z   (local was 22:47 CEST)
```

`timeZoneForSecondsFromGMT:` is the one thing that behaves, because it never
touches the database — which is why a caller can add two hours by hand and
believe the class works.

`knownTimeZoneNames` is 0 rather than ~600 because it reads
`_TZDIR/zone.tab`, i.e. `/usr/local/etc/zoneinfo/zone.tab`; the real file exists
(`/usr/share/zoneinfo/zone.tab`, 18813 bytes) and is never consulted. It fails
without a word, because `-[NSString stringWithContentsOfFile:]` on the missing
path yields `nil`, `componentsSeparatedByString:` on `nil` yields `nil`, and the
loop over `nil` yields the empty array.

## 3. Why it went unnoticed

**The name is preserved.** A caller that inspects `[tz name]` — the most natural
debugging step — sees `Europe/Berlin` and concludes the object is right. Only
`-secondsFromGMT` and `-abbreviation` reveal GMT, and `-description` renders as
`(nil) ((nil)) offset +0000`, which reads like an unconfigured object rather than
a wrong answer.

**The API can not fail, so nothing has to be handled.** `mulle_tz_context_with_name()`
always returns a freshly `malloc`ed context and never reports a load failure
(`__tzset` ends in `gmtload`), while

```objc
info = mulle_tz_context_with_name( (char *) [name cString], &size);
if( ! info)
{
   [self release];
   return( nil);
}
```

treats any non-`NULL` context as success. `+timeZoneWithName:` therefore never
returns `nil` for an unresolvable name, and `+systemTimeZone` never has to fall
back. The distinction between "loaded Berlin" and "loaded GMT because Berlin was
not found" does not exist anywhere in the code path.

**The golden test asserts the broken behaviour.** `test/NSTimeZone/default-timezone.stdout`
(kept, source deleted in `5ff4b36 "fixes for release"`) reads:

```
Default timezone: (null)
Default abbreviation: GMT
Default seconds from GMT: 0

System timezone: (null)
System abbreviation: GMT
System seconds from GMT: 0

PASS: Default timezone is GMT/UTC
```

which is the output of a test whose entire assertion was `if( seconds == 0) PASS`.
It was written in `7d948b8` together with the Windows platform implementations and
is correct for Windows; on Linux it *passes precisely when the timezone is
broken*, and it prints `(null)` for a name that would be `Europe/Berlin` on a
working build. Restoring that test today would re-bless the bug. The other test in
the directory, `simple.m`, only calls `[NSTimeZone mulleGMTTimeZone]`, so it is
immune by construction.

**Some paths still work, which hides the scope.** `timeZoneWithName:@"/usr/share/zoneinfo/Europe/Berlin"`
works, `timeZoneWithName:@"CET-1CEST,M3.5.0,M10.5.0/3"` works, and
`timeZoneForSecondsFromGMT:` works. Anyone who finds one working spelling
(MulleHeizer reached for `localtime_r` instead) has no reason to suspect the class.

## 4. The defect is three defects

They are independent; fixing only the first leaves the other two.

| # | where | what |
| --- | --- | --- |
| 1 | `private.h:78-82` / `tzfile.h:66-68` | `TZDIR` is `/usr/local/etc/zoneinfo` on Linux, so no zone name loads |
| 2 | `NSTimeZone+Posix.m:75-86` (`+_uncachedSystemTimeZone`) | `/etc/localtime` is never read; `TZ` unset ⇒ GMT, even with a correct `TZDIR` |
| 3 | `NSTimeZone+Posix.m:49-72` + `NSTimeZone.m:147-150` | a failed load is indistinguishable from a successful one, so an unresolvable name becomes a *named GMT* zone instead of `nil` |
| 4 | `NSTimeZone.m:47-67, 335-339` (`+localTimeZone`) | `_MulleObjCLocalTimeZone` is not a working proxy |

**On 2.** `_uncachedSystemTimeZone` is:

```objc
s = getenv( "TZ");
if( ! s)
   return( [_MulleGMTTimeZone sharedInstance]);
name = [NSString stringWithCString:s];
return( [NSTimeZone timeZoneWithName:name]);
```

With `TZ` unset — the normal case on a desktop Linux, where the zone lives in
`/etc/localtime` — it returns GMT *deliberately*, so no `TZDIR` fix changes
`+systemTimeZone`/`+defaultTimeZone`. Note also that the check accepts any value
of `TZ`, including the POSIX form `CET-1CEST,...`, which is a string that can only
be handled by `tzparse()`, and that `TZDEFAULT` is set to `"localtime"` (not
`/etc/localtime`), so the tzcode wall-clock path — `_tzsetwall()` via
`tzload(NULL, ...)`, which is what would read `/etc/localtime` — would look in
`$TZDIR/localtime` and is in any case never called by this category.

**On 4.** `+localTimeZone` returns `[[_MulleObjCLocalTimeZone new] autorelease]`,
whose only trick is:

```objc
- (void) forwardInvocation:(NSInvocation *) anInvocation
{
   [anInvocation setTarget:[NSTimeZone defaultTimeZone]];
   [anInvocation invoke];
}
```

`-forwardInvocation:` is reached only for selectors the class does **not**
implement. `-name`, `-data`, `-secondsFromGMT`, `-abbreviation`,
`-isDaylightSavingTime`, `-description`, `-hash` and `-isEqual:` are all
implemented by `NSTimeZone` itself, so the proxy answers each of them from its own
empty state and never forwards. Measured:

```
localTimeZone: name                       = (nil)
localTimeZone: offset                     = +0
localTimeZone: description                = (nil) ((nil)) offset +0000
localTimeZone: isEqual:defaultTimeZone    = NO
```

The intent ("a proxy so a later `+setDefaultTimeZone:` is reflected") is sound;
`NSProxy` is the class that implements it, and `NSTimeZone` is not one. As
written, `+localTimeZone` returns something that is not a timezone at all.

Two smaller items in the same area:

* `+timeZoneWithName:nil` **aborts** rather than answering `nil`:
  `NSParameterAssert( [name isKindOfClass:[NSString class]])` at
  `NSTimeZone+Posix.m:55`. Darwin returns `nil`.
* `+mulleGMTTimeZone` has `name = (nil)` (`-name` is not overridden on
  `_MulleGMTTimeZone`, only `-abbreviation`), so `[[NSTimeZone mulleGMTTimeZone] name]`
  is `nil` where `@"GMT"` is expected, and `-description` renders as
  `(nil) (GMT) offset +0000`.

## 5. Reproduction

The C probe is the shortest path and needs no Objective-C:

```c
/* tzprobe2.c */
#define _BSD_SOURCE
#define _DEFAULT_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

extern void   *mulle_tz_context_with_name( char *, size_t *);
extern long    mulle_get_gmt_offset_for_time_interval( void *, time_t);
extern char   *_mulle_get_zoneinfo_path( void);

static void   probe( const char *name, time_t t)
{
   size_t   size;
   void     *ctx;

   ctx = mulle_tz_context_with_name( (char *) name, &size);
   printf( "  %-40s offset=%+ld\n",
           name,
           mulle_get_gmt_offset_for_time_interval( ctx, t));
}

int main( void)
{
   time_t   t;

   t = time( NULL);
   printf( "TZDIR in use = %s\n", _mulle_get_zoneinfo_path());
   probe( "Europe/Berlin", t);                       /* +0    - tzload failed */
   probe( "/usr/share/zoneinfo/Europe/Berlin", t);   /* +7200 - reader is fine */
   probe( "/etc/localtime", t);                      /* +7200 */
   probe( "CET-1CEST,M3.5.0,M10.5.0/3", t);          /* +7200 - tzparse path */
   return( 0);
}
```

and the wrong literal can be found in a built library without running anything:

```
$ ar p libMulleFoundation.a localtime.c.o | strings | grep zoneinfo
/usr/local/etc/zoneinfo
```

Shortest Objective-C repro, needing nothing but the framework (and the reason to
run it inside `@autoreleasepool`/`+initialize` is that `NSTimeZone`'s tables are
set up there):

```objc
   NSTimeZone  *tz;

   tz = [NSTimeZone timeZoneWithName:@"Europe/Berlin"];
   assert( ! [tz isEqual:[NSTimeZone mulleGMTTimeZone]]);   // fails: it *is* GMT
   assert( [tz secondsFromGMT] != 0);                        // fails
   assert( [tz abbreviation] != nil);                        // passes, but is @"GMT"

   assert( [NSTimeZone timeZoneWithName:@"Bogus/Nowhere"] == nil);   // fails
```

The expected answers depend on the host, so a *test* has to pin the host zone
explicitly — `TZ=Europe/Berlin` is not enough on its own, because it is read only
by `+_uncachedSystemTimeZone` and passes through the same broken lookup (probe
above: `name=Europe/Berlin`, `offset=+0`). Either set `TZ=/usr/share/zoneinfo/Europe/Berlin`
(absolute — works today), or assert against a `TZDIR`-relative lookup that the
build guarantees.

## 6. Suggested fix

**1. Give the build a `TZDIR`.** The `#ifdef __APPLE__` in `private.h` is the
whole problem; tzcode's own default is `tzdir`-less for a reason, but this tree
ships on Linux. Either

```diff
-#ifdef __APPLE__
+/* private.h is included before tzfile.h by localtime.c, so this wins there */
+#ifndef TZDIR
 #define TZDIR  "/usr/share/zoneinfo"
 #endif
```

in `private.h`, and nothing else is needed: `localtime.c` is the only file that
includes either header, and it includes `private.h` (line 54) **before**
`tzfile.h` (line 55), so `#ifndef TZDIR` here takes effect and `tzfile.h`'s
fallback becomes dead code. (`tzfile.h`'s own default should probably be changed
to `/usr/share/zoneinfo` as well, since it is a vendored file and the next
reader will look there first.)

Passing it from the build (`-DTZDIR=...`) works too and is how a packager would
override it, but a `TZDIR` definition belongs in `MulleObjCPosixFoundation`, and
it should not be *only* a compile-time constant: `zoneinfo` is not under
`/usr/share` on the BSDs or Nix, so honouring a `MULLE_TZDIR` environment
variable and falling back to `/usr/share/zoneinfo` would cover those.

**2. Read `/etc/localtime` when `TZ` is unset.** In `+_uncachedSystemTimeZone`,
the tzcode answer already exists: `_tzsetwall()`/`tzload(NULL, ...)`. Reaching it
needs `TZDEFAULT` to be `"/etc/localtime"` (or an absolute-path load of that
file), otherwise `tzload(NULL)` resolves against `$TZDIR` and misses it again.
Failing that, `[NSTimeZone timeZoneWithName:@"/etc/localtime"]` is the direct
route and is proven to work in §2.

**3. Let a failed lookup be visible.** `mulle_tz_context_with_name()` needs a way
to say "this name did not resolve" (return `NULL`, or an out-parameter the way
`size` already is), and `-[NSTimeZone initWithName:]` must then return `nil`
rather than a named GMT zone. That is what makes defect 1 loud instead of silent,
and it is worth doing even if the `TZDIR` fix makes it unreachable in practice:
the next platform whose zoneinfo moves should not be discovered by a wrong
offset.

**4. `+localTimeZone`:** either make the forwarder a real `NSProxy` subclass,
or drop the proxy and forward explicitly for the methods that exist
(`-name`, `-data`, `-secondsFromGMT`, `-secondsFromGMTForDate:`, `-abbreviation`,
`-abbreviationForDate:`, `-isDaylightSavingTime`, `-isDaylightSavingTimeForDate:`,
`-description`), and note that `-hash`/`-isEqual:` can not be forwarded
meaningfully at all. Returning `[self defaultTimeZone]` and documenting that the
"later `+setDefaultTimeZone:` is reflected" property is lost would be honest and
would fix every observable above.

## 7. Copies that carry the defect

Only the first two rows are source; the amalgamation rows are what consumers
actually link, and the fix has to be refreshed into them or it does not reach a
project that depends on the umbrella.

| file | note |
| --- | --- |
| `MulleObjCPosixFoundation/src/Timezone/{private.h,tzfile.h,localtime.c}` | canonical tzcode; `private.h:78-82` is the `TZDIR` guard |
| `MulleObjCPosixFoundation/src/NSTimeZone+Posix.m` | `initWithName:` (49-72), `_uncachedSystemTimeZone` (75-86), abbrev/offset readers (207-266) |
| `MulleObjCStandardFoundation/src/TimeZone/NSTimeZone.m` | the class: proxy (47-67), `timeZoneWithName:` (147-150), `localTimeZone` (335-339) |
| `MulleFoundation/src/MulleObjCPosixFoundation/{private.h,tzfile.h,localtime.c,NSTimeZone+Posix.m}` | **amalgamation** — same lines, what `MulleHeizer` linked |
| `MulleFoundationBase/src/MulleObjCStandardFoundation/NSTimeZone.m` | amalgamation, same lines |
| `MulleObjCOSFoundation.borked/src/Posix/**`, `pre-split/MulleObjCOSFoundation/src/Posix/**` | dead layouts |
| `cmake-git-only-example/stash/MulleFoundationBase/...` | stale copy |

`MulleObjCLinuxFoundation` is not affected — it only adds
`-_timeIntervalSince1970ForTM:` and touches no zone file.

Verified byte-identical for `private.h` in all four copies I checked (the
`#ifdef __APPLE__` is at 78-82 in every one of them), so this is a single defect
duplicated by the amalgamation, not a divergence.

## 8. Where this report is filed

In `MulleObjCPosixFoundation`, beside `BUGREPORT-createDirectoryAtPath-intermediates.md`,
because this is the repository that owns the root cause (defects 1-3) and the only
plausible home that does **not** ignore markdown:

| repository | `.gitignore` | bug reports tracked |
| --- | --- | --- |
| `MulleObjCPosixFoundation` | (no `/*.md` rule) | 1 |
| `MulleObjCOSBaseFoundation` | (no `/*.md` rule) | 2 |
| `MulleObjCOSFoundation` | `/*.md` at line 88 | 0 |
| `MulleObjCStandardFoundation` | `/*.md` at line 75 | 0 |

That is not a technicality. `BUGREPORT-NSTask-currentDirectoryPath.md` sits in
`MulleObjCOSFoundation` untracked *and ignored* — it can not be committed without
`-f`, which is how that report, whose own subject is a fix that "has been lost
once already", can be lost again. This one is deliberately filed where `git add`
works.

Consequences for the work, not the report:

* defects 1-3 are fixed here;
* defect 4 (`+localTimeZone`) belongs to `MulleObjCStandardFoundation`;
* the regression test of §9 goes to `MulleObjCOSFoundation/test/NSTimeZone/`,
  next to `simple.m` and the `default-timezone.stdout` that has to be revised;
* every fix has to be refreshed into the amalgamation copies in `MulleFoundation`
  and `MulleFoundationBase` or it does not reach a consumer.

## 9. Regression test

`test/NSTimeZone/` already exists and must not be re-populated with the deleted
`default-timezone.m` as it was — its assertion (`secondsFromGMT == 0 ⇒ PASS`)
passes on a broken build. What the test has to assert, in this order:

1. a **named** zone loads with its real offset — `timeZoneWithName:@"Europe/Berlin"`
   is **not** `mulleGMTTimeZone`, and its `secondsFromGMT` for a fixed date is
   `+7200` in summer / `+3600` in winter. Selecting the date explicitly is the
   point: it also proves DST rules were loaded, which the offset alone does not.
2. `abbreviation` is `CEST`/`CET`, not `GMT` — the cheapest detector of "the name
   loaded but the data did not".
3. `timeZoneWithName:@"Bogus/Nowhere"]` is `nil` (defect 3), so an unresolvable
   name can never be mistaken for GMT.
4. `[[NSTimeZone localTimeZone] isEqual:[NSTimeZone defaultTimeZone]]` is `YES`
   and `[localTimeZone name]` is not `nil` (defect 4).
5. `knownTimeZoneNames` is non-empty, or at least not 0 (defect 1, database
   level, and it fails on the `zone.tab` path rather than the tzfile path).
6. With `TZ` unset and `/etc/localtime` pointing at `Europe/Berlin`,
   `[[NSTimeZone defaultTimeZone] secondsFromGMT]` is not 0 (defect 2).

Item 5 and 6 need the host zone to be known; the test should derive its
expectation from `readlink /etc/localtime` rather than hard-code CEST, or skip
with a message when `/etc/localtime` is GMT. `test/NSTimeZone/default-timezone.stdout`
should be regenerated or deleted, because as it stands it documents GMT as the
expected default.

## 10. Workaround in place

MulleHeizer renders local times with POSIX `localtime_r`/`strftime("%Z")`/
`strftime("%z")` and does not call `NSTimeZone` at all, with a comment at the
point of use recording why. That is the right call for a consumer and the wrong
outcome for the framework: it means the bug has no consumers left to notice it,
and the next consumer to reach for `NSCalendarDate`, `NSDateFormatter` or
`[NSTimeZone timeZoneWithName:]` gets an off-by-the-offset rendering with no error
anywhere.

## 11. One-sentence summary

On Linux `TZDIR` resolves to the tzcode default `/usr/local/etc/zoneinfo`, which
does not exist, so `tzload()` fails for every zone name, `__tzset()` silently
substitutes GMT, and because neither `mulle_tz_context_with_name()` nor
`-[NSTimeZone initWithName:]` can report that, every named zone becomes a
plausible-looking named GMT timezone — compounded by `+_uncachedSystemTimeZone`
never reading `/etc/localtime` and by `+localTimeZone` returning a forwarder that
can not forward.
