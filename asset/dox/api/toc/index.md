# MulleObjCPosixFoundation Library Documentation for AI
<!-- Keywords: posix, objc, foundation, categories, syscalls, timezone, locale -->

## 1. Introduction & Purpose

- Supplies the POSIX/Unix implementations for the platform-specific "future"
  functionality that `MulleObjCOSBaseFoundation` declares but leaves
  unimplemented. It is the Unix counterpart to `MulleObjCDarwinFoundation` and
  `MulleObjCWindowsFoundation`.
- It solves the problem of porting Foundation to Unix: instead of new classes,
  the behaviour is added to existing Foundation classes with Objective-C
  categories backed by system calls (`open`, `read`, `write`, `stat`,
  `opendir`, `select`, `dlopen`, `fork`/`exec` via mulle-spawn, `locale`,
  `strftime`/`strptime`, `tzfile`).
- Key features: file and directory management, bundle loading and symbol
  lookup, file handles and pipes, process info, run loop input via `select()`,
  task launching, time zones, locales, date formatting, `NSLog`, and POSIX
  error-domain helpers.
- Relationship: A component of MulleFoundation. It depends directly on
  `MulleObjCOSBaseFoundation` (see section 7) and is the foundation layer used
  by `MulleObjCStandardFoundation`/`MulleObjCTimeFoundation` on Unix.

## 2. Key Concepts & Design Philosophy

- **"Future" protocols.** `MulleObjCOSBaseFoundation` declares many methods in
  `( Future)` / `( OSSpecificFuture)` categories conforming to `MulleObjCFuture`.
  This library provides the concrete POSIX bodies for those methods. At runtime
  the method set is unified; source-wise the declarations live in the base
  library and the implementations live here.
- **Categories, not classes.** Only one new class is introduced
  (`_NSPosixDateFormatter`). Everything else is a category on an existing
  Foundation class (`NSFileManager`, `NSBundle`, `NSData`, `NSDate`,
  `NSCalendarDate`, `NSDirectoryEnumerator`, `NSFileHandle`, `NSPipe`,
  `NSProcessInfo`, `NSRunLoop`, `NSTask`, `NSTimeZone`, `NSUserDefaults`,
  `NSLocale`, `NSDateFormatter`).
- **Central include/import headers.** `src/include.h`, `src/import.h` and their
  private variants plus generated `src/reflect/*` headers keep dependency
  includes out of the library sources.
- **UTF-8 character locale.** `NSLocale( Posix) +load` calls
  `mulle_posix_setup_utf8_locale()` so the C library hands back UTF-8. Only
  `LC_CTYPE` is changed; `LC_NUMERIC` and `LC_TIME` stay at `"C"`, which the
  library's `strtod`/`strftime` code assumes.
- **POSIX error domain.** Failures are reported through `NSPOSIXErrorDomain`,
  which is installed with `MulleObjCSetPosixErrorDomain()` before a syscall;
  `[NSError mulleExtract]` then captures `errno`.
- **Delegation to mulle libraries.** Buffer/allocator work uses
  mulle-allocator and mulle-buffer, page allocation uses mulle-mmap, task
  spawning uses mulle-spawn, and locking uses mulle-thread.

## 3. Core API & Data Structures

All signatures below are copied verbatim from the headers (this project's
public/private headers, or the dependency header that declares the method this
project implements).

### 3.1. `NSError+Posix.h`

- Purpose: identify and install the POSIX error domain.
- Public symbols:
  - `MULLE_OBJC_POSIX_FOUNDATION_GLOBAL NSString *NSPOSIXErrorDomain;` — the
    global error domain string `@"NSPOSIXError"`.
  - `void MulleObjCSetPosixErrorDomain( void);` — sets the current error domain
    so a subsequent `[NSError mulleExtract]` produces an `NSPOSIXErrorDomain`
    error.

### 3.2. `NSLog.h`

- Purpose: `NSLog` entry points that print to `stderr` and `syslog`.
- Public functions:
  - `void NSLog( NSString *format, ...);` — format and log a message.
  - `void NSLogv( NSString *format, va_list args);` — `va_list` variant.
  - `void NSLogArguments( NSString *format, mulle_vararg_list args);` —
    `mulle_vararg_list` variant.
- Note: `NSLogv`/`NSLogArguments` create an autorelease pool because `%@`
  arguments commonly build temporary strings. `__NSLogPriority` (an `int`,
  default `LOG_WARNING`) controls the `syslog` priority.

### 3.3. `mulle-posix-tm.h`

- Purpose: C helpers bridging `struct tm` (POSIX, 0-based month, years since
  1900) and `struct mulle_mini_tm` (1-based month, absolute year), plus lenient
  `strptime` parsing.
- Public functions:
  - `int mulle_posix_tm_from_string_with_format( struct tm *tm, char **c_str_p, char *c_format, locale_t locale, int is_lenient);`
    — parse with `strptime`; `is_lenient` augments unparsed fields from the
    current time. Returns 0 on success, -1 on failure.
  - `void mulle_posix_tm_invalidate( struct tm *tm);` — fill every field with
    `INT_MIN` to mark it unparsed.
  - `int mulle_posix_tm_is_invalid( struct tm *tm);` — whether required fields
    are still invalid.
  - `unsigned int mulle_posix_tm_augment( struct tm *tm, struct tm *now);` —
    fill invalid fields from `now`; returns the number of fields filled.
  - `static inline struct mulle_mini_tm mulle_posix_tm_get_mini_tm( struct tm *src);`
    — convert a `struct tm` to a `struct mulle_mini_tm`.
  - `static inline void mulle_posix_tm_init_with_mini_tm( struct tm *dst, struct mulle_mini_tm src);`
    — convert a `struct mulle_mini_tm` to a `struct tm`.
  - `void mulle_posix_tm_init_with_time( struct tm *tm, time_t time);` — fill
    via `gmtime_r`.
  - `time_t mulle_posix_tm_get_time( struct tm *tm);` — convert a `struct tm`
    back to a `time_t` (treated as GMT).
  - `void mulle_posix_tm_init_with_interval1970( struct tm *tm, double timeInterval, int offset);`
    — fill from a 1970-based interval plus a GMT offset.

### 3.4. `NSLocale+Posix.h`

- Purpose: POSIX locale data and `locale_t` access.
- `@interface NSLocale( Posix)` — implementation category (no additional
  public selectors declared in the header).
- `@interface NSLocale( PosixFuture) < MulleObjCFuture>`
  - `+ (NSString *) systemLocalePath;` — path to the system locale data.
  - `- (id) _localeInfoForKey:(id) key;` — look up raw locale info.
- Implemented by this project (see `NSLocale+Posix.m`):
  - `+ (NSArray *) availableLocaleIdentifiers` — enumerates glibc's
    `locale-archive` plus per-locale directories (Linux) or the directories
    below `_PATH_LOCALE`/`PATH_LOCALE` (BSD/Darwin); always includes `"C"` and
    `"POSIX"`. Result is cached and marked thread-safe.
  - `+ (NSString *) auxiliaryLocalePath` — `@"/usr/share/mulle-locale"`.
  - `+ (NSDictionary *) auxiliaryLocaleInfoForIdentifier:(NSString *) identifier`
    — loads `<auxiliaryLocalePath>/<identifier>.plist` if present.
  - `- (instancetype) initWithLocaleIdentifier:(NSString *) name` — builds a
    `locale_t` via `newlocale`, retrying with `.UTF-8`/`.utf8`, finally
    falling back to `"C"`.
  - `- (locale_t) xlocale MULLE_OBJC_THREADSAFE_METHOD` — the cached
    `locale_t` (immutable after init, safe to share).

### 3.5. `_NSPosixDateFormatter.h`

- Purpose: the 10.0-style `NSDateFormatter` implementation using
  `strftime`/`strptime` and xlocale.
- `@interface _NSPosixDateFormatter : NSDateFormatter`
  - `- (BOOL) getObjectValue:(id *) obj forString:(NSString *) string range:(NSRange *) rangep error:(NSError **) error;`
  - `- (NSString *) stringFromDate:(id) date;`
  - `- (id) dateFromString:(NSString *) s;`
- `@interface NSDateFormatter( PosixFuture) < MulleObjCFuture>`
  - `- (size_t) _printTM:(struct tm *) tm buffer:(char *) buf length:(size_t) len formatUTF8String:(char *) c_format locale:(NSLocale *) locale;`
  - `- (NSDate *) _parseDateWithUTF8String:(char **) string formatUTF8String:(char *) c_format locale:(NSLocale *) locale;`
- `+load` registers `_NSPosixDateFormatter` for
  `NSDateFormatterBehavior10_0`. Locally handled conversions are `%n`, `%z`,
  `%Z`, `%y`, `%Y`, `%m`, `%d`, `%H`, `%M`, `%S` and `%F` (milliseconds); all
  others are deferred to `strftime`/`strptime`.

### 3.6. Foundation categories implemented by this project

These methods are declared as "future" API in the dependency headers; the
signatures below match those declarations and the implementations in
`src/*.m`.

#### `NSFileManager( Posix)` (`NSFileManager+Posix.m`)

- Directories and paths:
  - `- (BOOL) changeCurrentDirectoryPath:(NSString *) path;` — `chdir`.
  - `- (NSString *) currentDirectoryPath;` — `getcwd`.
  - `- (BOOL) createDirectoryAtPath:(NSString *) path withIntermediateDirectories:(BOOL) createIntermediates attributes:(NSDictionary *) attributes error:(NSError **) error;`
    — `mkdir`, optionally creating parents.
  - `- (int) _createDirectoryAtPath:(NSString *) path attributes:(NSDictionary *) attributes;`
    — single `mkdir`, returns 0, `EEXIST`/`ENOENT` or -1.
- Queries:
  - `- (BOOL) fileExistsAtPath:(NSString *) path;`
  - `- (BOOL) fileExistsAtPath:(NSString *) path isDirectory:(BOOL *) isDirectory;`
  - `- (BOOL) isDeletableFileAtPath:(NSString *) path;`
  - `- (BOOL) isExecutableFileAtPath:(NSString *) path;`
  - `- (BOOL) isReadableFileAtPath:(NSString *) path;`
  - `- (BOOL) isWritableFileAtPath:(NSString *) path;`
- Attributes:
  - `- (NSDictionary *) fileAttributesAtPath:(NSString *) path traverseLink:(BOOL) flag;`
  - `- (NSDictionary *) attributesOfItemAtPath:(NSString *) path error:(NSError **) error;`
    — never traverses symlinks.
  - `- (NSDictionary *) fileSystemAttributesAtPath:(NSString *) path;` —
    `statvfs`-based free/total size and node counts.
  - `- (NSDictionary *) attributesOfFileSystemForPath:(NSString *) path error:(NSError **) error;`
  - `- (BOOL) setAttributes:(NSDictionary *) attributes ofItemAtPath:(NSString *) path error:(NSError **) error;`
    — applies `NSFileOwnerAccountID`/`NSFileGroupOwnerAccountID` (`chown`),
    `NSFilePosixPermissions` (`chmod`) and `NSFileModificationDate`
    (`utimensat`).
- Symbolic links:
  - `- (BOOL) createSymbolicLinkAtPath:(NSString *) path withDestinationPath:(NSString *) otherpath error:(NSError **) error;`
  - `- (NSString *) pathContentOfSymbolicLinkAtPath:(NSString *) path;`
  - `- (NSString *) destinationOfSymbolicLinkAtPath:(NSString *) path error:(NSError **) error;`
- Enumeration:
  - `- (NSArray *) directoryContentsAtPath:(NSString *) path;` — shallow
    `readdir`, skipping `.`, `..`, and `._*`.
- Copy/move/remove:
  - `- (BOOL) movePath:(NSString *) src toPath:(NSString *) dest handler:(id) handler;`
  - `- (BOOL) moveItemAtPath:(NSString *) srcPath toPath:(NSString *) dstPath error:(NSError **) error;`
  - `- (BOOL) copyPath:(NSString *) src toPath:(NSString *) dest handler:(id) handler;`
  - `- (BOOL) copyItemAtPath:(NSString *) fromPath toPath:(NSString *) toPath error:(NSError **) error;`
  - `- (BOOL) _removeFileAtPath:(NSString *) path;` — `unlink`.
  - `- (BOOL) _removeEmptyDirectoryItemAtPath:(NSString *) path;` — `rmdir`.
- Internal: `_isValidDirectoryContentsFilenameAsCString:`, `_isDirectory:`,
  `_getCTimeFromStat:`, `_getMTimeFromStat:`, `_itemAttributesAtPath:traverseLink:`,
  `_pathContentOfSymbolicLinkAtPath:recursively:`.

#### `NSBundle( Posix)` (`NSBundle+Posix.m`)

- `+ (BOOL) isBundleFilesystemExtension:(NSString *) extension;` — true for
  `"so"`.
- `- (NSString *) builtInPlugInsPath;`
- `- (NSString *) pathForAuxiliaryExecutable:(NSString *) executableName;`
- `- (NSString *) privateFrameworksPath;`
- `- (NSString *) sharedFrameworksPath;`
- `- (NSString *) sharedSupportPath;`
- `+ (NSBundle *) bundleForClass:(Class) aClass;` — resolves the shared library
  via `dladdr`, falling back to `mainBundle`.
- `- (BOOL) loadBundle;` / `- (BOOL) unloadBundle;` — `dlopen`/`dlclose`.
- `NSBundle( MulleSymbolLookup)`:
  - `- (void *) mulleLookupSymbolUTF8String:(char *) name;` — `dlsym`.
  - `- (void *) mulleLookupSymbol:(NSString *) name;`
- Internal POSIX layout helpers: `_posixResourcePath`, `_posixBuiltInPlugInsPath`,
  `_posixPathForAuxiliaryExecutable:`, `_posixPrivateFrameworksPath`,
  `_posixSharedFrameworksPath`, `_posixSharedSupportPath`, `_posixExecutablePath`,
  `_loadFailureReason`.

#### `NSData( Posix)` (`NSData+Posix.m`)

- `- (instancetype) initWithContentsOfFile:(NSString *) path;` — `open`/`read`
  (supports pipes via `read()` loop); returns nil and sets `errno` on failure.
- `- (BOOL) writeToFile:(NSString *) path atomically:(BOOL) flag;` — writes and
  optionally renames a `~` temporary into place.
- `- (BOOL) writeToFile:(NSString *) path atomically:(BOOL) flag error:(NSError **) p_error;`
- `+ (void) load` installs the mmap system page size.

#### `NSDate( Posix)` and `NSCalendarDate( Posix)` (`NSDate+Posix.m`, `NSCalendarDate+Posix.m`)

- `NSDate( Posix)` (declared in `NSDate+Posix-Private.h`):
  - `- (instancetype) _initWithTM:(struct tm *) tm nanoseconds:(unsigned long long) nanoseconds timeZone:(NSTimeZone *) tz;`
  - `- (struct timeval) _timevalForSelect;` — remaining time as a `timeval` for
    `select()`.
- `_MulleObjCConcreteCalendarDate( Posix)`:
  - `+ (instancetype) newWithTimeIntervalSince1970:(NSTimeInterval) timeInterval timeZone:(NSTimeZone *) timeZone;`
  - `+ (instancetype) newWithTimeIntervalSince1970:(NSTimeInterval) timeInterval;`
  - `- (NSTimeInterval) timeIntervalSince1970;`
  - `- (NSTimeInterval) timeIntervalSinceReferenceDate;`
- `NSCalendarDate( Posix)`:
  - `- (instancetype) _initWithTM:(struct tm *) tm nanoseconds:(unsigned long long) nanoseconds timeZone:(NSTimeZone *) tz;`
  - `- (instancetype) init;`
  - `- (instancetype) initWithTimeIntervalSince1970:(NSTimeInterval) timeInterval;`
  - `- (instancetype) mulleInitWithTimeIntervalSince1970:(NSTimeInterval) timeInterval timeZone:(NSTimeZone *) tz;`
  - `- (instancetype) initWithTimeIntervalSinceReferenceDate:(NSTimeInterval) timeInterval;`
  - `- (instancetype) mulleInitWithTimeIntervalSinceReferenceDate:(NSTimeInterval) timeInterval timeZone:(NSTimeZone *) tz;`
  - `- (instancetype) mulleInitWithDate:(NSDate *) date timeZone:(NSTimeZone *) tz;`
  - `- (instancetype) initWithDate:(NSDate *) date;`
  - `- (NSDate *) date;`
  - `- (NSCalendarDate *) dateByAddingYears:(NSInteger) years months:(NSInteger) months days:(NSInteger) days hours:(NSInteger) hours minutes:(NSInteger) minutes seconds:(NSInteger) seconds;`

#### `NSDirectoryEnumerator( Posix)` (`NSDirectoryEnumerator+Posix.m`)

- `- (instancetype) initWithFileManager:(NSFileManager *) manager rootPath:(NSString *) root inheritedPath:(NSString *) inherited;`
  — `opendir`; a plain file yields an enumerator that yields nothing.
- `- (NSString *) _nextEntry:(int *) is_dir;` — `readdir`, skipping `.`/`..`.
- `- (void) _close;` — `closedir`.

#### `NSFileHandle( Posix)` (`NSFileHandle+Posix.m`)

- `+ (instancetype) _fileHandleWithPath:(NSString *) path mode:(enum _MulleObjCOpenMode) mode;`
- `- (instancetype) initWithFileDescriptor:(int) fd closeOnDealloc:(BOOL) flag;`
- `+ (instancetype) fileHandleWithStandardInput;`
- `+ (instancetype) fileHandleWithStandardOutput;`
- `+ (instancetype) fileHandleWithStandardError;`
- `- (ssize_t) _readBytes:(void *) buf length:(size_t) len;` — retries `EINTR`,
  tracks `NSFileHandleStateEOF`/`Pipe`/`Again`.
- `- (size_t) _writeBytes:(void *) buf length:(size_t) len;`
- `- (unsigned long long) _seek:(unsigned long long) offset mode:(enum _MulleObjCSeekMode) mode;`
- `- (void) synchronizeFile;` — `sync`.
- `- (void) _truncate:(unsigned long long) offset;` — `ftruncate`.

#### `NSPipe( Posix)` (`NSPipe+Posix.m`)

- `- (instancetype) init;` — creates a `pipe(2)` and wraps both ends in
  `NSFileHandle`s with `closeOnDealloc:YES`.

#### `NSProcessInfo( Posix)` (`NSProcessInfo+Posix.m`)

- `- (NSInteger) processIdentifier;` — `getpid`.
- `- (NSString *) operatingSystemVersionString;` — `uname` sysname + release.
- `- (void) mulleSetEnvironmentValue:(NSString *) value forKey:(NSString *) key;`
  — `setenv`/`unsetenv` and updates the cached environment.

#### `NSRunLoop( Posix)` (`NSRunLoop+Posix.m`)

- `- (enum MulleRunLoopInputState) _acceptInputForRunLoopMode:(struct MulleRunLoopMode *) mode beforeDate:(NSDate *) date;`
  — waits on `select()` for registered file descriptors, firing timers first.
- `- (void) _addFileDescriptor:(int) fd forMode:(struct MulleRunLoopMode *) mode;`
- `- (void) _finalizePosix:(struct posix_mode *) ctxt;`

#### `NSTask( Posix)` (`NSTask+Posix.m`)

- `- (void) launch;` — builds `argv`/`envp`, wires the three standard streams
  and launches the child through mulle-spawn. The parent's own pipe ends are
  marked `FD_CLOEXEC` and later closed so the child sees EOF.

#### `NSTimeZone( Posix)` (`NSTimeZone+Posix.m`)

- `- (instancetype) initWithName:(NSString *) name;` — loads a tzfile (name,
  absolute path or POSIX TZ string) into `NSData`.
- `+ (NSTimeZone *) _uncachedSystemTimeZone;` — `TZ` then `/etc/localtime`,
  else GMT.
- `+ (NSArray *) availableLocaleIdentifiers;`
- `+ (NSArray *) knownTimeZoneNames;` — parses the zone.tab file.
- `+ (NSDictionary *) abbreviationDictionary;` — built-in abbreviation map.
- `- (NSInteger) mulleSecondsFromGMTForTimeIntervalSince1970:(NSTimeInterval) interval;`
- `- (NSInteger) secondsFromGMTForDate:(NSDate *) aDate;`
- `- (NSString *) abbreviationForDate:(NSDate *) aDate;`
- `- (BOOL) isDaylightSavingTimeForDate:(NSDate *) aDate;`

#### `NSUserDefaults( Posix)` (`NSUserDefaults+Posix.m`)

- `- (BOOL) _loadPersistentDomain:(NSMutableDictionary *) domain;` — reads a
  plist from `$MULLE_USER_DEFAULTS_DIR` or `~/.config`.
- `- (BOOL) _savePersistentDomain:(NSDictionary *) domain;` — atomically writes
  or removes that plist.

## 4. Performance Characteristics

- Most file operations are one or two syscalls: `stat`/`lstat`/`access` are
  O(1) with respect to path depth; `directoryContentsAtPath:` is O(n) in the
  number of directory entries and allocates an autoreleased array.
- `NSData -initWithContentsOfFile:` speculatively reads 4 KB and resizes to
  `st_size`, so a small file costs one read; pipes are read in 4 KB chunks.
- Locale enumeration (`+availableLocaleIdentifiers`) is expensive (it may mmap
  a multi-megabyte glibc archive) but is cached for the process lifetime and
  published thread-safely. The work is done outside the lock; racing threads
  may both enumerate, the first to publish wins.
- Time zone data is loaded once per `NSTimeZone` instance into `NSData` and
  queried by binary search inside the tzfile routines, O(log n).
- `NSRunLoop` keeps a sorted fd array and rebuilds the `fd_set` per `select`;
  cost is O(k) in the number of registered descriptors.
- Thread-safety: `NSLocale`'s `locale_t` and cached identifiers are shared and
  read-only; the `_keyValues` cache is lock-protected. `NSFileManager`,
  `NSProcessInfo`, `NSUserDefaults` and `NSFileHandle` are declared thread-safe
  by the base library; most other categories inherit their class's contract.

## 5. AI Usage Recommendations & Patterns

- Best Practices:
  - Use the normal Foundation API (`[NSData dataWithContentsOfFile:]`,
    `[NSFileManager defaultManager]`, `NSDateFormatter`, `NSTimeZone`, ...).
    The POSIX behaviour is selected automatically at load time; there is rarely
    a reason to call a `_`-prefixed or `Posix` method directly.
  - Call `MulleObjCSetPosixErrorDomain()` before a POSIX call if you then want
    `[NSError mulleExtract]` (or the `...error:` variants) to return an
    `NSPOSIXErrorDomain` error.
  - Prefer `NSTimeZone`/`NSLocale` instances over touching `locale_t` or tzfile
    data yourself; `-xlocale` is exposed only for the date formatter.
  - Use the `...error:` variants (`writeToFile:atomically:error:`,
    `attributesOfItemAtPath:error:`, ...) when you need to distinguish failure
    causes.
- Common Pitfalls:
  - `NSDateFormatter` behavior is fixed to `NSDateFormatterBehavior10_0` on
    POSIX; do not assume 10.4 (ICU) behaviour.
  - `+availableLocaleIdentifiers` and `+knownTimeZoneNames` read the host's
    locale/zoneinfo files; containers may lack them (the locale list then
    degrades to `"C"`/`"POSIX"`).
  - `NSFileManager -moveItemAtPath:toPath:error:` and `-copyItemAtPath:toPath:error:`
    are implemented in terms of copy+remove and do not preserve all metadata;
    an existing destination aborts the operation.
  - `NSTask -launch` throws (it does not silently report exit 127) when the
    child cannot be started; catch or let it propagate.
  - `NSRunLoop` uses `select()`, so it is limited by `FD_SETSIZE`.
- Idiomatic usage: import `<MulleObjCPosixFoundation/MulleObjCPosixFoundation.h>`
  (which pulls in `NSLog.h`, `NSError+Posix.h`, `NSLocale+Posix.h`) and use
  plain Foundation calls; use `NSLog` for diagnostics and
  `NSPOSIXErrorDomain` for error reporting.

## 6. Integration Examples

### Example 1: Reading and writing a file with the POSIX-backed NSData

```objc
#import <MulleObjCPosixFoundation/MulleObjCPosixFoundation.h>

int   main( int argc, char *argv[])
{
   NSData   *data;
   BOOL     didWrite;

   data = [NSData dataWithContentsOfFile:@"/etc/hostname"];
   if( ! data)
   {
      NSLog( @"could not read /etc/hostname");
      return( 1);
   }

   didWrite = [data writeToFile:@"/tmp/hostname.copy"
                     atomically:YES];
   if( ! didWrite)
   {
      NSLog( @"could not write copy");
      return( 1);
   }

   return( 0);
}
```

### Example 2: Creating a directory and inspecting attributes

```objc
#import <MulleObjCPosixFoundation/MulleObjCPosixFoundation.h>

int   main( int argc, char *argv[])
{
   NSDictionary   *attributes;
   NSError        *error;
   NSFileManager  *manager;
   BOOL           isDirectory;

   manager = [NSFileManager defaultManager];
   error   = nil;

   if( ! [manager createDirectoryAtPath:@"/tmp/mulle-demo"
            withIntermediateDirectories:YES
                             attributes:nil
                                  error:&error])
   {
      NSLog( @"create failed: %@", error);
      return( 1);
   }

   if( ! [manager fileExistsAtPath:@"/tmp/mulle-demo"
                       isDirectory:&isDirectory] || ! isDirectory)
   {
      NSLog( @"not a directory");
      return( 1);
   }

   attributes = [manager attributesOfItemAtPath:@"/tmp/mulle-demo"
                                          error:&error];
   NSLog( @"attributes: %@", attributes);

   return( 0);
}
```

### Example 3: Formatting a date in a time zone

```objc
#import <MulleObjCPosixFoundation/MulleObjCPosixFoundation.h>

int   main( int argc, char *argv[])
{
   NSDate           *date;
   NSDateFormatter  *formatter;
   NSTimeZone       *timeZone;
   NSString         *s;

   timeZone  = [NSTimeZone timeZoneWithName:@"Europe/Berlin"];
   formatter = [NSDateFormatter dateFormatterWithDateFormat:@"%Y-%m-%d %H:%M:%S %Z"
                                      allowNaturalLanguage:NO];
   [formatter setTimeZone:timeZone];

   date = [NSDate date];
   s    = [formatter stringFromDate:date];
   NSLog( @"%@", s);

   return( 0);
}
```

### Example 4: Launching a task

```objc
#import <MulleObjCPosixFoundation/MulleObjCPosixFoundation.h>

int   main( int argc, char *argv[])
{
   NSArray   *arguments;
   NSTask    *task;

   arguments = [NSArray arrayWithObjects:@"/bin/echo", @"hello", nil];

   task = [NSTask launchedTaskWithLaunchPath:@"/bin/echo"
                                   arguments:arguments];
   [task waitUntilExit];

   NSLog( @"termination status: %ld", (long) [task terminationStatus]);
   return( 0);
}
```

## 7. Dependencies

- `MulleObjCOSBaseFoundation` — the only direct `mulle-sde` dependency (per
  `.mulle/etc/sourcetree/config` and `clib.json`). It declares the "future"
  methods this project implements and provides the private headers used
  throughout.

<!-- Note: mulle-spawn, mulle-mmap, mulle-buffer, mulle-allocator and
     mulle-thread are used as transitive/constituent libraries of the runtime,
     not as direct sourcetree dependencies of this project. -->
