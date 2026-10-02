//
//  NSLocale+Posix.m
//  MulleObjCOSFoundation
//
//  Copyright (c) 2016 Nat! - Mulle kybernetiK.
//  All rights reserved.
//
//
//  Redistribution and use in source and binary forms, with or without
//  modification, are permitted provided that the following conditions are met:
//
//  Redistributions of source code must retain the above copyright notice, this
//  list of conditions and the following disclaimer.
//
//  Redistributions in binary form must reproduce the above copyright notice,
//  this list of conditions and the following disclaimer in the documentation
//  and/or other materials provided with the distribution.
//
//  Neither the name of Mulle kybernetiK nor the names of its contributors
//  may be used to endorse or promote products derived from this software
//  without specific prior written permission.
//
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
//  AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
//  IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
//  ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
//  LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
//  CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
//  SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
//  INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
//  CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
//  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
//  POSSIBILITY OF SUCH DAMAGE.
//
// define, that make things POSIXly
#define _XOPEN_SOURCE 700

#import "import-private.h"

#import "NSLocale+Posix.h"
#import "NSError+Posix.h"

// other files in this library
#import "NSLocale+Posix-Private.h"

// other libraries
#import <MulleObjCOSBaseFoundation/NSString+CString.h>

// std-c and dependencies
#include <locale.h>
#include <langinfo.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>


// We want to *run* UTF-8, not adapt to the language of the user: the C
// library is put into a UTF-8 character locale, so that everything it hands
// back is UTF-8. Only LC_CTYPE is set, LC_NUMERIC and LC_TIME stay at "C",
// which this library assumes for strtod, strftime and friends.
//
// "C.UTF-8" is the preferred name, but not every libc knows it, so the
// language neutral spellings are tried first. If the system can not do UTF-8
// at all, nothing happens and the C string encoding adapts to whatever is
// available (see mulle_posix_cstring_encoding).
void   mulle_posix_setup_utf8_locale( void)
{
   static char   *names[] =
   {
      "C.UTF-8", "C.utf8", "C.UTF8",
      "en_US.UTF-8", "en_US.utf8",
      "UTF-8",
      NULL
   };
   char         *codeset;
   char         **p;

   codeset = nl_langinfo( CODESET);
   if( codeset && ! strcmp( codeset, "UTF-8"))
      return;

   for( p = names; *p; p++)
      if( setlocale( LC_CTYPE, *p))
         return;
}


NSStringEncoding   mulle_posix_cstring_encoding( void)
{
   return( mulle_cstring_encoding_for_codeset( nl_langinfo( CODESET)));
}


#define match( key, identifier, type, code)               \
   if( [key isEqualToString:identifier ])                 \
   {                                                      \
      return( make_mulle_locale_key_info( type, code));   \
   }


struct mulle_locale_key_info   mulle_locale_map_string_key_to_local_key( NSString *key)
{
   match( key, NSLocaleAlternateQuotationBeginDelimiterKey, -1, 0);
   match( key, NSLocaleAlternateQuotationEndDelimiterKey, -1, 0);
   // a calendar is an NSCalendar object, which is above this library; the
   // string that -calendarIdentifier answers does not need the OS either
   match( key, NSLocaleCalendar, -1, 0);
   // collationIdentifier, collatorIdentifier, countryCode, languageCode,
   // measurementSystem, the quotation and alternate quotation delimiters,
   // scriptCode, usesMetricSystem and variantCode follow from the identifier
   // alone, so they are answered platform independently by NSLocale (see
   // -_derivedLocaleInfoForKey:). Asking the OS for the language is wrong: a
   // locale that was constructed from an identifier keeps that identifier even
   // when the OS has no data for it (and falls back to "C").
   match( key, NSLocaleCollationIdentifier, -1, 0);
   match( key, NSLocaleCollatorIdentifier, -1, 0);
   match( key, NSLocaleCountryCode, -1, 0);
   // int_curr_symbol is the ISO 4217 code, which is what NSLocaleCurrencyCode
   // documents
   match( key, NSLocaleCurrencyCode, CONV_INFO, CONV_INT_CURRENCY_SYMBOL);
   match( key, NSLocaleCurrencySymbol, CONV_INFO, CONV_CURRENCY_SYMBOL);
   match( key, NSLocaleDecimalSeparator, CONV_INFO, CONV_DECIMAL_POINT);
   // an exemplar character set is CLDR data, POSIX has no source for it
   match( key, NSLocaleExemplarCharacterSet, -1, 0);
   // NSLocaleGroupingSeparator is the thousands separator, not the (internal)
   // grouping pattern conv->grouping
   match( key, NSLocaleGroupingSeparator, CONV_INFO, CONV_THOUSANDS_SEPERATOR);
   match( key, NSLocaleIdentifier, IDENTIFIER_INFO, 0);
   match( key, NSLocaleLanguageCode, -1, 0);
   match( key, NSLocaleMeasurementSystem, -1, 0);
   match( key, NSLocaleQuotationBeginDelimiterKey, -1, 0);
   match( key, NSLocaleQuotationEndDelimiterKey, -1, 0);
   match( key, NSLocaleScriptCode, -1, 0);
   match( key, NSLocaleUsesMetricSystem, -1, 0);
   match( key, NSLocaleVariantCode, -1, 0);

   return( make_mulle_locale_key_info( ERROR_INFO, 0));
}


// int_curr_symbol is padded with a blank (and possibly other whitespace)
static NSString   *mulle_locale_trimmed_string( char *s)
{
   char     buf[ 64];
   size_t   len;

   len = strlen( s);
   while( len && (s[ len - 1] == ' ' || s[ len - 1] == '\t'))
      --len;

   if( len >= sizeof( buf))
      return( [NSString stringWithCString:s]);

   memcpy( buf, s, len);
   buf[ len] = 0;
   return( [NSString stringWithCString:buf]);
}


id    mulle_locale_lconv_value( struct lconv *conv, int code)
{
   char   *s;
   int    nr;
   BOOL   flag;

   nr   = -1;
   s    = NULL;
   flag = NO;

   switch( code)
   {
   default                             : return( nil);
   case CONV_DECIMAL_POINT             : s = conv->decimal_point; break;
   case CONV_THOUSANDS_SEPERATOR       : s = conv->thousands_sep; break;
   case CONV_GROUPING                  : s = conv->grouping; break;
   case CONV_INT_CURRENCY_SYMBOL       : s = conv->int_curr_symbol; break;

   case CONV_CURRENCY_SYMBOL           : s = conv->currency_symbol; break;
   case CONV_MONEY_DECIMAL_POINT       : s = conv->mon_decimal_point; break;
   case CONV_MONEY_THOUSANDS_SEPERATOR : s = conv->mon_thousands_sep; break;
   case CONV_MONEY_GROUPING            : s = conv->mon_grouping; break;

   case CONV_POSITIVE_SIGN             : s = conv->positive_sign; break;
   case CONV_NEGATIVE_SIGN             : s = conv->negative_sign; break;
   case CONV_INT_FRACTIONAL_DIGITS     : nr = conv->int_frac_digits; break;
   case CONV_FRACTIONAL_DIGITS         : nr = conv->frac_digits; break;

   case CONV_POSITIVE_VALUE_CURRENCY_SYMBOL_PRECEDES               : flag = conv->p_cs_precedes; break;
   case CONV_POSITIVE_VALUE_CURRENCY_SYMBOL_SEPARATED_BY_SPACE     : flag = conv->p_sep_by_space; break;
   case CONV_NEGATIVE_VALUE_CURRENCY_SYMBOL_PRECEDES               : flag = conv->n_cs_precedes; break;
   case CONV_NEGATIVE_VALUE_CURRENCY_SYMBOL_SEPARATED_BY_SPACE     : flag = conv->n_sep_by_space; break;

   case CONV_POSITIVE_SIGN_POSITION                                : nr   = conv->p_sign_posn; break;
   case CONV_NEGATIVE_SIGN_POSITION                                : nr   = conv->n_sign_posn; break;
   case CONV_INT_POSITIVE_VALUE_CURRENCY_SYMBOL_PRECEDES           : flag = conv->int_p_cs_precedes; break;
   case CONV_INT_NEGATIVE_VALUE_CURRENCY_SYMBOL_PRECEDES           : flag = conv->int_n_cs_precedes; break;

   case CONV_INT_POSITIVE_VALUE_CURRENCY_SYMBOL_SEPARATED_BY_SPACE : flag = conv->int_p_sep_by_space; break;
   case CONV_INT_NEGATIVE_VALUE_CURRENCY_SYMBOL_SEPARATED_BY_SPACE : flag = conv->int_n_sep_by_space; break;
   case CONV_INT_POSITIVE_SIGN_POSITION                            : flag = conv->int_p_sign_posn; break;
   case CONV_INT_NEGATIVE_SIGN_POSITION                            : flag = conv->int_n_sign_posn; break;
   }

   if( s)
   {
      if( code == CONV_INT_CURRENCY_SYMBOL)
         return( mulle_locale_trimmed_string( s));
      return( [NSString stringWithCString:s]);
   }

   if( nr != -1)
      return( [NSNumber numberWithInt:nr]);

   return( [NSNumber numberWithBool:flag]);
}


@implementation NSLocale( Posix)

static NSArray                *identifiers;
static mulle_thread_mutex_t   identifiersLock;


+ (void) load
{
   // run UTF-8, see mulle_posix_setup_utf8_locale
   mulle_posix_setup_utf8_locale();

   if( mulle_thread_mutex_init( &identifiersLock))
      abort();
}


+ (void) unload
{
   mulle_thread_mutex_lock( &identifiersLock);
   if( identifiers) // avoid +initialize due to -release (noticed in trace)
   {
      [identifiers release];
      identifiers = nil;
   }
   mulle_thread_mutex_unlock( &identifiersLock);
   mulle_thread_mutex_done( &identifiersLock);
}

// How a POSIX libc knows its locales differs by family, and "locale -a" reads
// the very same sources we read here, in process (instead of shelling out to
// "/usr/bin/locale -a", which forks a shell, needs a writable temp directory
// and silently degrades on hosts that lack either):
//
//   glibc (Linux):  a single binary "locale-archive" that glibc mmaps, plus
//                   one directory per locale below /usr/lib/locale for the
//                   locales compiled outside the archive.
//   BSD / Darwin:   one directory per locale below /usr/share/locale (the
//                   _PATH_LOCALE, overridable with PATH_LOCALE). No archive.
//
// Neither has a public API, so we walk them ourselves.
#define MULLE_LOCALE_SHARE_DIRECTORY      "/usr/share/locale"


#if defined( __GLIBC__)
// The archive layout is stable and documented in glibc <locale/locarchive.h>:
//
//   struct locarhead
//   {
//      uint32_t  magic;             // 0xde020109
//      uint32_t  serial;
//      uint32_t  namehash_offset;   // file offset of the name hash table
//      uint32_t  namehash_used;
//      uint32_t  namehash_size;     // number of slots in that table
//      uint32_t  string_offset;     // file offset of the string table
//      uint32_t  string_used;
//      uint32_t  string_size;
//      ... locrectab and sumhash follow
//   };
//   struct namehashent { uint32_t hashval, name_offset, locrec_offset; };
//
// All fields are host endian. name_offset is an absolute file offset into the
// archive, an entry is occupied when locrec_offset is non-zero (the occupied
// slots are not packed at the front), and the name is a NUL terminated C
// string. This is the exact walk "locale -a" performs.
//
// https://www.man7.org/linux/man-pages/man1/localedef.1.html
#define MULLE_LOCALE_ARCHIVE             "/usr/lib/locale/locale-archive"
#define MULLE_LOCALE_DIRECTORY           "/usr/lib/locale"

#define MULLE_LOCALE_ARCHIVE_MAGIC       0xde020109U
#define MULLE_LOCALE_ARCHIVE_MAGIC_SWAP  0x090102deU

#define MULLE_LOCAR_NAMEHASH_OFFSET      2
#define MULLE_LOCAR_NAMEHASH_SIZE        4
#define MULLE_LOCAR_STRING_OFFSET        5
#define MULLE_LOCAR_STRING_SIZE          7
#define MULLE_LOCAR_HEADER_U32S          14
#define MULLE_LOCAR_NAMEHASH_ENTRY_SIZE  12


// The header and hash entries are uint32 in host byte order. The magic tells
// a foreign endian archive apart, so a big endian host can read a little
// endian archive and vice versa.
static uint32_t   mulle_locale_read_u32( unsigned char *bytes, BOOL swap)
{
   uint32_t   value;

   memcpy( &value, bytes, 4);
   if( swap)
      value = ((value & 0x000000FFU) << 24) |
              ((value & 0x0000FF00U) <<  8) |
              ((value & 0x00FF0000U) >>  8) |
              ((value & 0xFF000000U) >> 24);
   return( value);
}
#endif


// Adds identifier to the ordered result, skipping empty names and the ones
// that were collected before (the archive and the directory scan can overlap).
static void   mulle_locale_add_identifier( NSMutableArray *result,
                                           NSMutableSet *seen,
                                           NSString *identifier)
{
   if( ! [identifier length])
      return;
   if( [seen containsObject:identifier])
      return;
   [seen addObject:identifier];
   [result addObject:identifier];
}


#if defined( __GLIBC__)
// Adds the locale names of the glibc locale archive to the result. Returns NO
// if there is no readable archive (a stripped container image for instance).
// A malformed archive is rejected rather than walked out of bounds.
static BOOL   mulle_locale_collect_archive( NSMutableArray *result,
                                            NSMutableSet *seen,
                                            NSString *path)
{
   NSData         *data;
   unsigned char  *bytes;
   NSUInteger     length;
   uint32_t       magic;
   uint32_t       namehash_offset;
   uint32_t       namehash_size;
   uint32_t       string_offset;
   uint32_t       string_size;
   uint32_t       name_offset;
   uint32_t       locrec_offset;
   BOOL           swap;
   NSUInteger     i;
   NSUInteger     offset;
   NSString       *name;

   data = [NSData dataWithContentsOfFile:path];
   if( ! data)
      return( NO);

   length = [data length];
   if( length < MULLE_LOCAR_HEADER_U32S * 4)
      return( NO);

   bytes = (unsigned char *) [data bytes];

   magic = mulle_locale_read_u32( bytes, NO);
   swap  = (magic != MULLE_LOCALE_ARCHIVE_MAGIC);
   if( swap && magic != MULLE_LOCALE_ARCHIVE_MAGIC_SWAP)
      return( NO);

   namehash_offset = mulle_locale_read_u32( bytes + MULLE_LOCAR_NAMEHASH_OFFSET * 4, swap);
   namehash_size   = mulle_locale_read_u32( bytes + MULLE_LOCAR_NAMEHASH_SIZE   * 4, swap);
   string_offset   = mulle_locale_read_u32( bytes + MULLE_LOCAR_STRING_OFFSET   * 4, swap);
   string_size     = mulle_locale_read_u32( bytes + MULLE_LOCAR_STRING_SIZE     * 4, swap);

   if( (uint64_t) namehash_offset +
          (uint64_t) namehash_size * MULLE_LOCAR_NAMEHASH_ENTRY_SIZE > length)
      return( NO);
   if( (uint64_t) string_offset + string_size > length)
      return( NO);

   for( i = 0; i < namehash_size; i++)
   {
      offset        = namehash_offset + i * MULLE_LOCAR_NAMEHASH_ENTRY_SIZE;
      name_offset   = mulle_locale_read_u32( bytes + offset + 4, swap);
      locrec_offset = mulle_locale_read_u32( bytes + offset + 8, swap);

      if( ! locrec_offset)   // empty hash slot
         continue;
      if( name_offset < string_offset || name_offset >= string_offset + string_size)
         continue;

      name = [NSString stringWithCString:(char *) bytes + name_offset];
      mulle_locale_add_identifier( result, seen, name);
   }
   return( YES);
}
#endif


// Adds the names of the per-locale directories below path. When marker is not
// nil, a directory only counts as a locale when it carries that category
// (glibc tags every real locale with LC_IDENTIFICATION, which tells it apart
// from a directory that merely holds translations). "UTF-8" is the charmaps
// pseudo entry that the BSD "locale -a" skips as well.
static void   mulle_locale_collect_directories( NSMutableArray *result,
                                                NSMutableSet *seen,
                                                NSString *path,
                                                NSString *marker)
{
   NSFileManager   *manager;
   NSArray         *contents;
   NSString        *name;
   NSString        *child;
   NSString        *probe;
   BOOL            isDirectory;
   NSUInteger      i;
   NSUInteger      n;

   manager  = [NSFileManager defaultManager];
   contents = [manager directoryContentsAtPath:path];
   n        = [contents count];
   for( i = 0; i < n; i++)
   {
      name = [contents objectAtIndex:i];
      if( [name hasPrefix:@"."])       // "." and "..", should the OS report them
         continue;
      if( [name isEqualToString:@"UTF-8"])
         continue;

      child = [path stringByAppendingPathComponent:name];
      if( ! [manager fileExistsAtPath:child isDirectory:&isDirectory] || ! isDirectory)
         continue;

      if( marker)
      {
         probe = [child stringByAppendingPathComponent:marker];
         if( ! [manager fileExistsAtPath:probe])
            continue;
      }
      mulle_locale_add_identifier( result, seen, name);
   }
}


// The enumeration costs a few file system reads (the archive can be several MB
// big) and never changes for the lifetime of a process, so it is done at most
// once and cached. The work happens outside the lock; two racing threads may
// both enumerate and the first one to publish wins.
+ (NSArray *) availableLocaleIdentifiers
{
   NSMutableArray   *collected;
   NSMutableSet     *seen;
   NSArray          *result;

   mulle_thread_mutex_lock( &identifiersLock);
   if( identifiers)
   {
      result = [[identifiers retain] autorelease];
      mulle_thread_mutex_unlock( &identifiersLock);
      return( result);
   }
   mulle_thread_mutex_unlock( &identifiersLock);

   collected = [NSMutableArray array];
   seen      = [NSMutableSet set];

   // POSIX.2 4.34.3: "C" and "POSIX" are always available. They are the
   // documented floor this method never goes below, even on a host whose
   // locale data can not be found. The old code degraded silently to a
   // hardcoded "en_US.utf8" list instead.
   mulle_locale_add_identifier( collected, seen, @"C");
   mulle_locale_add_identifier( collected, seen, @"POSIX");

#if defined( __GLIBC__)
   // glibc: the mmapped archive first, then the per-locale directories, so
   // the order is stable
   mulle_locale_collect_archive( collected, seen,
                                 [NSString stringWithCString:MULLE_LOCALE_ARCHIVE]);
   mulle_locale_collect_directories( collected, seen,
                                     [NSString stringWithCString:MULLE_LOCALE_DIRECTORY],
                                     @"LC_IDENTIFICATION");
#else
   // The BSD derived libcs: one directory per locale below _PATH_LOCALE
   // (/usr/share/locale, overridable with PATH_LOCALE), no archive. This is
   // what their "locale -a" scans as well.
   {
      char   *directory;

      directory = getenv( "PATH_LOCALE");
      if( ! directory)
         directory = MULLE_LOCALE_SHARE_DIRECTORY;

      mulle_locale_collect_directories( collected, seen,
                                        [NSString stringWithCString:directory],
                                        nil);
   }
#endif

   result = collected;

   mulle_thread_mutex_lock( &identifiersLock);
   if( ! identifiers)
   {
      identifiers = [result copy];
      [identifiers mulleSetThreadSafe:YES];
   }
   result = [[identifiers retain] autorelease];
   mulle_thread_mutex_unlock( &identifiersLock);

   return( result);
}


/*
Try to load a dictionary named:

de_DE.plist
{
    NSAMPMDesignation = ("vorm.", "nachm.");
    NSDateFormatString = "%A, %e. %B %Y";
    NSDateTimeOrdering = DMYH;
    NSEarlierTimeDesignations = ("fr\U00fcher", vorher, letzten );
    NSHourNameDesignations = (
        (0, mitternachts, Mitternacht),
        (8, morgens, Morgen),
        (12, mittags, Mittag),
        (15, nachmittags, Nachmittag),
        (18, abends, Abend)
    );
    NSLaterTimeDesignations = ("n\U00e4chsten");
    NSMonthNameArray = (
        Januar,
        Februar,
        "M\U00e4rz",
        April,
        Mai,
        Juni,
        Juli,
        August,
        September,
        Oktober,
        November,
        Dezember
    );
    NSNextDayDesignations = (morgen);
    NSNextNextDayDesignations = ( "\U00fcbermorgen");
    NSPriorDayDesignations = ( gestern);
    NSShortDateFormatString = "%d.%m.%y";
    NSShortMonthNameArray = (Jan, Feb, Mrz, Apr, Mai, Jun, Jul, Aug, Sep, Okt, Nov, Dez);
    NSShortTimeDateFormatString = "%d.%m.%y %H:%M";
    NSShortWeekDayNameArray = (So, Mo, Di, Mi, Do, Fr, Sa);
    NSThisDayDesignations = ( heute, jetzt);
    NSTimeDateFormatString = "%A, %e. %B %Y %1H:%M Uhr %Z";
    NSTimeFormatString = "%H:%M:%S";
    NSWeekDayNameArray = (Sonntag, Montag, Dienstag, Mittwoch, Donnerstag, Freitag, Samstag);
    NSYearMonthWeekDesignations = ( Jahr, Monat, Woche);
}
*/

+ (NSString *) auxiliaryLocalePath
{
   return( @"/usr/share/mulle-locale");
}


+ (NSDictionary *) auxiliaryLocaleInfoForIdentifier:(NSString *) identifier
{
   NSString  *path;

   path = [[self auxiliaryLocalePath] stringByAppendingPathComponent:identifier];
   path = [path stringByAppendingPathExtension:@"plist"];
   return( [NSDictionary dictionaryWithContentsOfFile:path]);
}


// inserts a codeset into "language[_country][.codeset][@modifier]"
static NSString   *mulle_locale_identifier_with_codeset( NSString *identifier, NSString *codeset)
{
   NSArray    *components;
   NSString   *base;
   NSString   *modifier;

   components = [identifier componentsSeparatedByString:@"@"];
   base       = [[components objectAtIndex:0] stringByAppendingString:codeset];
   if( [components count] > 1)
   {
      modifier = [components objectAtIndex:1];
      base     = [base stringByAppendingString:[@"@" stringByAppendingString:modifier]];
   }
   return( base);
}


- (instancetype) initWithLocaleIdentifier:(NSString *) name
{
   locale_t       xlocale;
   NSDictionary   *auxInfo;

   MulleObjCSetPosixErrorDomain();

   if( ! name)
   {
      [self release];
      return( nil);
   }

   // POSIX locale names may omit the codeset (like "en_US"), but newlocale()
   // rejects them then. Retry with the common UTF-8 spellings and, as a last
   // resort, fall back to the portable "C" locale - a NSLocale should never
   // be nil.
   xlocale = newlocale( LC_ALL_MASK, [name UTF8String], NULL);
   if( ! xlocale)
      xlocale = newlocale( LC_ALL_MASK,
                           [mulle_locale_identifier_with_codeset( name, @".UTF-8") UTF8String],
                           NULL);
   if( ! xlocale)
      xlocale = newlocale( LC_ALL_MASK,
                           [mulle_locale_identifier_with_codeset( name, @".utf8") UTF8String],
                           NULL);
   if( ! xlocale)
      xlocale = newlocale( LC_ALL_MASK, "C", NULL);

   if( ! xlocale)
   {
      [self release];
      return( nil);
   }

   _xlocale    = xlocale;
   _identifier = [name copy];
   _keyValues  = [NSMutableDictionary new];
   _lock       = [NSLock new];

   // _keyValues is only accessed under _lock, so tell TAO that it may be
   // messaged from any thread (it has no real thread affinity).
   [_keyValues mulleSetThreadSafe:YES];

   // Precompute the keys that follow from the identifier (and merge in the
   // locale's data file if it has one). That is what lets -objectForKey:
   // answer them without taking _lock and without reparsing the identifier.
   auxInfo = [[self class] auxiliaryLocaleInfoForIdentifier:name];
   [self _setupDerivedLocaleValues:auxInfo];

   return( self);
}


- (void) dealloc
{
   [_identifier release];
   [_keyValues release];
   [_derivedValues release];
   [_lock release];
   if( _xlocale)
      freelocale( _xlocale);

   [super dealloc];
}


- (locale_t) xlocale   MULLE_OBJC_THREADSAFE_METHOD
{
   return( _xlocale);
}

@end

