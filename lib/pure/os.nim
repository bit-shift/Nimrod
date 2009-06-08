#
#
#            Nimrod's Runtime Library
#        (c) Copyright 2009 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module contains basic operating system facilities like
## retrieving environment variables, reading command line arguments,
## working with directories, running shell commands, etc.
## This module is -- like any other basic library -- platform independant.
{.deadCodeElim: on.}

{.push debugger: off.}

import
  strutils, times

when defined(windows):
  import winlean
elif defined(posix): 
  import posix
else:
  {.error: "OS module not ported to your operating system!".}

include "system/ansi_c"

# copied from excpt.nim, because I don't want to make this template public
template newException(exceptn, message: expr): expr =
  block: # open a new scope
    var
      e: ref exceptn
    new(e)
    e.msg = message
    e

const
  doslike = defined(windows) or defined(OS2) or defined(DOS)
    # DOS-like filesystem

when defined(Nimdoc): # only for proper documentation:
  const
    CurDir* = '.'
      ## The constant string used by the operating system to refer to the
      ## current directory.
      ##
      ## For example: '.' for POSIX or ':' for the classic Macintosh.

    ParDir* = ".."
      ## The constant string used by the operating system to refer to the parent
      ## directory.
      ##
      ## For example: ".." for POSIX or "::" for the classic Macintosh.

    DirSep* = '/'
      ## The character used by the operating system to separate pathname
      ## components, for example, '/' for POSIX or ':' for the classic
      ## Macintosh.
      ##
      ## Note that knowing this is not sufficient to be able to parse or
      ## concatenate pathnames -- use `splitPath` and `joinPath` instead --
      ## but it is occasionally useful.

    AltSep* = '/'
      ## An alternative character used by the operating system to separate
      ## pathname components, or the same as `DirSep` if only one separator
      ## character exists. This is set to '/' on Windows systems where `DirSep`
      ## is a backslash.

    PathSep* = ':'
      ## The character conventionally used by the operating system to separate
      ## search patch components (as in PATH), such as ':' for POSIX or ';' for
      ## Windows.

    FileSystemCaseSensitive* = True
      ## True if the file system is case sensitive, false otherwise. Used by
      ## `cmpPaths` to compare filenames properly.

    ExeExt* = ""
      ## The file extension of native executables. For example:
      ## "" on UNIX, "exe" on Windows.

    ScriptExt* = ""
      ## The file extension of a script file. For example: "" on UNIX,
      ## "bat" on Windows.

elif defined(macos):
  const
    curdir* = ':'
    pardir* = "::"
    dirsep* = ':'
    altsep* = dirsep
    pathsep* = ','
    FileSystemCaseSensitive* = false
    ExeExt* = ""
    ScriptExt* = ""

  #  MacOS paths
  #  ===========
  #  MacOS directory separator is a colon ":" which is the only character not
  #  allowed in filenames.
  #
  #  A path containing no colon or which begins with a colon is a partial path.
  #  E.g. ":kalle:petter" ":kalle" "kalle"
  #
  #  All other paths are full (absolute) paths. E.g. "HD:kalle:" "HD:"
  #  When generating paths, one is safe if one ensures that all partial paths
  #  begin with a colon, and all full paths end with a colon.
  #  In full paths the first name (e g HD above) is the name of a mounted
  #  volume.
  #  These names are not unique, because, for instance, two diskettes with the
  #  same names could be inserted. This means that paths on MacOS is not
  #  waterproof. In case of equal names the first volume found will do.
  #  Two colons "::" are the relative path to the parent. Three is to the
  #  grandparent etc.
elif doslike:
  const
    curdir* = '.'
    pardir* = ".."
    dirsep* = '\\' # seperator within paths
    altsep* = '/'
    pathSep* = ';' # seperator between paths
    FileSystemCaseSensitive* = false
    ExeExt* = "exe"
    ScriptExt* = "bat"
elif defined(PalmOS) or defined(MorphOS):
  const
    dirsep* = '/'
    altsep* = dirsep
    PathSep* = ';'
    pardir* = ".."
    FileSystemCaseSensitive* = false
    ExeExt* = ""
    ScriptExt* = ""
elif defined(RISCOS):
  const
    dirsep* = '.'
    altsep* = '.'
    pardir* = ".." # is this correct?
    pathSep* = ','
    FileSystemCaseSensitive* = true
    ExeExt* = ""
    ScriptExt* = ""
else: # UNIX-like operating system
  const
    curdir* = '.'
    pardir* = ".."
    dirsep* = '/'
    altsep* = dirsep
    pathSep* = ':'
    FileSystemCaseSensitive* = true
    ExeExt* = ""
    ScriptExt* = ""

const
  ExtSep* = '.'
    ## The character which separates the base filename from the extension;
    ## for example, the '.' in ``os.nim``.

# procs dealing with command line arguments:
proc paramCount*(): int
  ## Returns the number of command line arguments given to the
  ## application.

proc paramStr*(i: int): string
  ## Returns the `i`-th command line arguments given to the
  ## application.
  ##
  ## `i` should be in the range `1..paramCount()`, else
  ## the `EOutOfIndex` exception is raised.

proc OSError*(msg: string = "") {.noinline.} =
  ## raises an EOS exception with the given message ``msg``.
  ## If ``msg == ""``, the operating system's error flag
  ## (``errno``) is converted to a readable error message. On Windows
  ## ``GetLastError`` is checked before ``errno``.
  ## If no error flag is set, the message ``unknown OS error`` is used.
  if len(msg) == 0:
    when defined(Windows):
      var err = GetLastError()
      if err != 0'i32:
        # sigh, why is this is so difficult?
        var msgbuf: cstring
        if FormatMessageA(0x00000100 or 0x00001000 or 0x00000200,
                          nil, err, 0, addr(msgbuf), 0, nil) != 0'i32:
          var m = $msgbuf
          if msgbuf != nil:
            LocalFree(msgbuf)
          raise newException(EOS, m)
    if errno != 0'i32:
      raise newException(EOS, $os.strerror(errno))
    else:
      raise newException(EOS, "unknown OS error")
  else:
    raise newException(EOS, msg)

proc UnixToNativePath*(path: string): string {.noSideEffect.} =
  ## Converts an UNIX-like path to a native one.
  ##
  ## On an UNIX system this does nothing. Else it converts
  ## '/', '.', '..' to the appropriate things.
  when defined(unix):
    result = path
  else:
    var start: int
    if path[0] == '/':
      # an absolute path
      when doslike:
        result = r"C:\"
      elif defined(macos):
        result = "" # must not start with ':'
      else:
        result = $dirSep
      start = 1
    elif path[0] == '.' and path[1] == '/':
      # current directory
      result = $curdir
      start = 2
    else:
      result = ""
      start = 0

    var i = start
    while i < len(path): # ../../../ --> ::::
      if path[i] == '.' and path[i+1] == '.' and path[i+2] == '/':
        # parent directory
        when defined(macos):
          if result[high(result)] == ':':
            add result, ':'
          else:
            add result, pardir
        else:
          add result, pardir & dirSep
        inc(i, 3)
      elif path[i] == '/':
        add result, dirSep
        inc(i)
      else:
        add result, path[i]
        inc(i)

proc existsFile*(filename: string): bool =
  ## Returns true if the file exists, false otherwise.
  when defined(windows):
    var a = GetFileAttributesA(filename)
    if a != -1'i32:
      result = (a and FILE_ATTRIBUTE_DIRECTORY) == 0'i32
  else:
    var res: TStat
    return stat(filename, res) >= 0'i32 and S_ISREG(res.st_mode)

proc existsDir*(dir: string): bool =
  ## Returns true iff the directory `dir` exists. If `dir` is a file, false
  ## is returned.
  when defined(windows):
    var a = GetFileAttributesA(dir)
    if a != -1'i32:
      result = (a and FILE_ATTRIBUTE_DIRECTORY) != 0'i32
  else:
    var res: TStat
    return stat(dir, res) >= 0'i32 and S_ISDIR(res.st_mode)

proc getLastModificationTime*(file: string): TTime =
  ## Returns the `file`'s last modification time.
  when defined(posix):
    var res: TStat
    if stat(file, res) < 0'i32: OSError()
    return res.st_mtime
  else:
    var f: TWIN32_Find_Data
    var h = findfirstFileA(file, f)
    if h == -1'i32: OSError()
    result = winTimeToUnixTime(rdFileTime(f.ftLastWriteTime))
    findclose(h)

proc getLastAccessTime*(file: string): TTime =
  ## Returns the `file`'s last read or write access time.
  when defined(posix):
    var res: TStat
    if stat(file, res) < 0'i32: OSError()
    return res.st_atime
  else:
    var f: TWIN32_Find_Data
    var h = findfirstFileA(file, f)
    if h == -1'i32: OSError()
    result = winTimeToUnixTime(rdFileTime(f.ftLastAccessTime))
    findclose(h)

proc getCreationTime*(file: string): TTime = 
  ## Returns the `file`'s creation time.
  when defined(posix):
    var res: TStat
    if stat(file, res) < 0'i32: OSError()
    return res.st_ctime
  else:
    var f: TWIN32_Find_Data
    var h = findfirstFileA(file, f)
    if h == -1'i32: OSError()
    result = winTimeToUnixTime(rdFileTime(f.ftCreationTime))
    findclose(h)

proc fileNewer*(a, b: string): bool =
  ## Returns true if the file `a` is newer than file `b`, i.e. if `a`'s
  ## modification time is later than `b`'s.
  result = getLastModificationTime(a) - getLastModificationTime(b) > 0

proc getCurrentDir*(): string =
  ## Returns the current working directory.
  const bufsize = 512 # should be enough
  result = newString(bufsize)
  when defined(windows):
    var L = GetCurrentDirectoryA(bufsize, result)
    if L == 0'i32: OSError()
    setLen(result, L)
  else:
    if getcwd(result, bufsize) != nil:
      setlen(result, c_strlen(result))
    else:
      OSError()

proc setCurrentDir*(newDir: string) {.inline.} =
  ## Sets the current working directory; `EOS` is raised if
  ## `newDir` cannot been set.
  when defined(Windows):
    if SetCurrentDirectoryA(newDir) == 0'i32: OSError()
  else:
    if chdir(newDir) != 0'i32: OSError()

proc JoinPath*(head, tail: string): string {.noSideEffect.} =
  ## Joins two directory names to one.
  ##
  ## For example on Unix:
  ##
  ## ..code-block:: nimrod
  ##   JoinPath("usr", "lib")
  ##
  ## results in:
  ##
  ## ..code-block:: nimrod
  ##   "usr/lib"
  ##
  ## If head is the empty string, tail is returned.
  ## If tail is the empty string, head is returned.
  if len(head) == 0:
    result = tail
  elif head[len(head)-1] in {DirSep, AltSep}:
    if tail[0] in {DirSep, AltSep}:
      result = head & copy(tail, 1)
    else:
      result = head & tail
  else:
    if tail[0] in {DirSep, AltSep}:
      result = head & tail
    else:
      result = head & DirSep & tail

proc JoinPath*(parts: openarray[string]): string {.noSideEffect.} =
  ## The same as `JoinPath(head, tail)`, but works with any number
  ## of directory parts.
  result = parts[0]
  for i in 1..high(parts):
    result = JoinPath(result, parts[i])

proc `/` * (head, tail: string): string {.noSideEffect.} =
  ## The same as ``joinPath(head, tail)``
  return joinPath(head, tail)

proc SplitPath*(path: string, head, tail: var string) {.noSideEffect.} =
  ## Splits a directory into (head, tail), so that
  ## ``JoinPath(head, tail) == path``.
  ##
  ## Example: After ``SplitPath("usr/local/bin", head, tail)``,
  ## `head` is "usr/local" and `tail` is "bin".
  ## Example: After ``SplitPath("usr/local/bin/", head, tail)``,
  ## `head` is "usr/local/bin" and `tail` is "".
  var
    sepPos = -1
  for i in countdown(len(path)-1, 0):
    if path[i] in {dirsep, altsep}:
      sepPos = i
      break
  if sepPos >= 0:
    head = copy(path, 0, sepPos-1)
    tail = copy(path, sepPos+1)
  else:
    head = ""
    tail = path # make a string copy here

proc parentDir*(path: string): string {.noSideEffect.} =
  ## Returns the parent directory of `path`.
  ##
  ## This is often the same as the ``head`` result of ``splitPath``.
  ## If there is no parent, ``path`` is returned.
  ## Example: ``parentDir("/usr/local/bin") == "/usr/local"``.
  ## Example: ``parentDir("/usr/local/bin/") == "/usr/local"``.
  var
    sepPos = -1
    q = 1
  if path[len(path)-1] in {dirsep, altsep}:
    q = 2
  for i in countdown(len(path)-q, 0):
    if path[i] in {dirsep, altsep}:
      sepPos = i
      break
  if sepPos >= 0:
    result = copy(path, 0, sepPos-1)
  else:
    result = path

proc `/../` * (head, tail: string): string {.noSideEffect.} =
  ## The same as ``parentDir(head) / tail``
  return parentDir(head) / tail

proc normExt(ext: string): string =
  if ext == "" or ext[0] == extSep: result = ext # no copy needed here
  else: result = extSep & ext

proc searchExtPos(s: string): int =
  result = -1
  for i in countdown(len(s)-1, 0):
    if s[i] == extsep:
      result = i
      break
    elif s[i] in {dirsep, altsep}:
      break # do not skip over path

proc extractDir*(path: string): string {.noSideEffect.} =
  ## Extracts the directory of a given path. This is almost the
  ## same as the `head` result of `splitPath`, except that
  ## ``extractDir("/usr/lib/") == "/usr/lib/"``.
  if path.len == 0 or path[path.len-1] in {dirSep, altSep}:
    result = path
  else:
    var tail: string
    splitPath(path, result, tail)

proc extractFilename*(path: string): string {.noSideEffect.} =
  ## Extracts the filename of a given `path`. This is almost the
  ## same as the `tail` result of `splitPath`, except that
  ## ``extractFilename("/usr/lib/") == ""``.
  if path.len == 0 or path[path.len-1] in {dirSep, altSep}:
    result = ""
  else:
    var head: string
    splitPath(path, head, result)

proc expandFilename*(filename: string): string =
  ## Returns the full path of `filename`, raises EOS in case of an error.
  when defined(windows):
    var unused: cstring
    result = newString(3072)
    var L = GetFullPathNameA(filename, 3072'i32, result, unused)
    if L <= 0'i32 or L >= 3072'i32: OSError()
    setLen(result, L)
  else:
    var res = realpath(filename, nil)
    if res == nil: OSError()
    result = $res
    c_free(res)

proc SplitFilename*(filename: string, name, extension: var string) {.
  noSideEffect.} = 
  ## Splits a filename into (name, extension), so that
  ## ``name & extension == filename``.
  ##
  ## Example: After ``SplitFilename("usr/local/nimrodc.html", name, ext)``,
  ## `name` is "usr/local/nimrodc" and `ext` is ".html".
  ## It the file has no extension, extention is the empty string.
  var extPos = searchExtPos(filename)
  if extPos >= 0:
    name = copy(filename, 0, extPos-1)
    extension = copy(filename, extPos)
  else:
    name = filename # make a string copy here
    extension = ""

proc extractFileExt*(filename: string): string {.noSideEffect.} =
  ## Extracts the file extension of a given `filename`. This is the
  ## same as the `extension` result of `splitFilename`.
  var dummy: string
  splitFilename(filename, dummy, result)

proc extractFileTrunk*(filename: string): string {.noSideEffect.} =
  ## Extracts the file name of a given `filename`. This removes any
  ## directory information and the file extension.
  var dummy: string
  splitFilename(extractFilename(filename), result, dummy)

proc ChangeFileExt*(filename, ext: string): string {.noSideEffect.} =
  ## Changes the file extension to `ext`.
  ##
  ## If the `filename` has no extension, `ext` will be added.
  ## If `ext` == "" then any extension is removed.
  ## `Ext` should be given without the leading '.', because some
  ## filesystems may use a different character. (Although I know
  ## of none such beast.)
  var extPos = searchExtPos(filename)
  if extPos < 0: result = filename & normExt(ext)
  else: result = copy(filename, 0, extPos-1) & normExt(ext)

proc AppendFileExt*(filename, ext: string): string {.noSideEffect.} =
  ## Appends the file extension `ext` to `filename`, unless
  ## `filename` already has an extension.
  ##
  ## `Ext` should be given without the leading '.', because some
  ## filesystems may use a different character.
  ## (Although I know of none such beast.)
  var extPos = searchExtPos(filename)
  if extPos < 0: result = filename & normExt(ext)
  else: result = filename #make a string copy here

proc cmpPaths*(pathA, pathB: string): int {.noSideEffect.} =
  ## Compares two paths.
  ##
  ## On a case-sensitive filesystem this is done
  ## case-sensitively otherwise case-insensitively. Returns:
  ##
  ## | 0 iff pathA == pathB
  ## | < 0 iff pathA < pathB
  ## | > 0 iff pathA > pathB
  if FileSystemCaseSensitive:
    result = cmp(pathA, pathB)
  else:
    result = cmpIgnoreCase(pathA, pathB)

proc sameFile*(path1, path2: string): bool =
  ## Returns True if both pathname arguments refer to the same file or
  ## directory (as indicated by device number and i-node number).
  ## Raises an exception if an os.stat() call on either pathname fails.
  when defined(Windows):
    var
      a, b: TWin32FindData
    var resA = findfirstFileA(path1, a)
    var resB = findfirstFileA(path2, b)
    if resA != -1 and resB != -1:
      result = $a.cFileName == $b.cFileName
    else:
      # work around some ``findfirstFileA`` bugs
      result = cmpPaths(path1, path2) == 0
    if resA != -1: findclose(resA)
    if resB != -1: findclose(resB)
  else:
    var
      a, b: TStat
    if stat(path1, a) < 0'i32 or stat(path2, b) < 0'i32:
      result = cmpPaths(path1, path2) == 0 # be consistent with Windows
    else:
      result = a.st_dev == b.st_dev and a.st_ino == b.st_ino

proc sameFileContent*(path1, path2: string): bool =
  ## Returns True if both pathname arguments refer to files with identical
  ## content. Content is compared byte for byte.
  const
    bufSize = 8192 # 8K buffer
  var
    a, b: TFile
  if not openFile(a, path1): return false
  if not openFile(b, path2):
    closeFile(a)
    return false
  var bufA = alloc(bufsize)
  var bufB = alloc(bufsize)
  while True:
    var readA = readBuffer(a, bufA, bufsize)
    var readB = readBuffer(b, bufB, bufsize)
    if readA != readB:
      result = false
      break
    if readA == 0:
      result = true
      break
    result = equalMem(bufA, bufB, readA)
    if not result: break
    if readA != bufSize: break # end of file
  dealloc(bufA)
  dealloc(bufB)
  closeFile(a)
  closeFile(b)

proc copyFile*(dest, source: string) =
  ## Copies a file from `source` to `dest`. If this fails,
  ## `EOS` is raised.
  when defined(Windows):
    if CopyFileA(source, dest, 0'i32) == 0'i32: OSError()
  else:
    # generic version of copyFile which works for any platform:
    const
      bufSize = 8192 # 8K buffer
    var
      d, s: TFile
    if not openFile(s, source): OSError()
    if not openFile(d, dest, fmWrite):
      closeFile(s)
      OSError()
    var
      buf: Pointer = alloc(bufsize)
      bytesread, byteswritten: int
    while True:
      bytesread = readBuffer(s, buf, bufsize)
      byteswritten = writeBuffer(d, buf, bytesread)
      if bytesread != bufSize: break
      if bytesread != bytesWritten: OSError()
    dealloc(buf)
    closeFile(s)
    closeFile(d)

proc moveFile*(dest, source: string) =
  ## Moves a file from `source` to `dest`. If this fails, `EOS` is raised.
  if crename(source, dest) != 0'i32: OSError()

proc removeFile*(file: string) =
  ## Removes the `file`. If this fails, `EOS` is raised.
  if cremove(file) != 0'i32: OSError()

proc executeShellCommand*(command: string): int =
  ## Executes a shell command.
  ##
  ## Command has the form 'program args' where args are the command
  ## line arguments given to program. The proc returns the error code
  ## of the shell when it has finished. The proc does not return until
  ## the process has finished. To execute a program without having a
  ## shell involved, use the `executeProcess` proc of the `osproc`
  ## module.
  result = csystem(command)

var
  envComputed: bool = false
  environment: seq[string] = @[]

when defined(windows):
  # because we support Windows GUI applications, things get really
  # messy here...
  proc strEnd(cstr: CString, c = 0'i32): CString {.
    importc: "strchr", header: "<string.h>".}

  proc getEnvVarsC() =
    if not envComputed:
      var
        env = getEnvironmentStringsA()
        e = env
      if e == nil: return # an error occured
      while True:
        var eend = strEnd(e)
        add(environment, $e)
        e = cast[CString](cast[TAddress](eend)+1)
        if eend[1] == '\0': break
      envComputed = true
      discard FreeEnvironmentStringsA(env)

else:
  var
    gEnv {.importc: "gEnv".}: ptr array [0..10_000, CString]

  proc getEnvVarsC() =
    # retrieves the variables of char** env of C's main proc
    if not envComputed:
      var i = 0
      while True:
        if gEnv[i] == nil: break
        add environment, $gEnv[i]
        inc(i)
      envComputed = true

proc findEnvVar(key: string): int =
  getEnvVarsC()
  var temp = key & '='
  for i in 0..high(environment):
    if startsWith(environment[i], temp): return i
  return -1

proc getEnv*(key: string): string =
  ## Returns the value of the environment variable named `key`.
  ##
  ## If the variable does not exist, "" is returned. To distinguish
  ## whether a variable exists or it's value is just "", call
  ## `existsEnv(key)`.
  var i = findEnvVar(key)
  if i >= 0:
    return copy(environment[i], find(environment[i], '=')+1)
  else:
    var env = cgetenv(key)
    if env == nil: return ""
    result = $env

proc existsEnv*(key: string): bool =
  ## Checks whether the environment variable named `key` exists.
  ## Returns true if it exists, false otherwise.
  if cgetenv(key) != nil: return true
  else: return findEnvVar(key) >= 0

proc putEnv*(key, val: string) =
  ## Sets the value of the environment variable named `key` to `val`.
  ## If an error occurs, `EInvalidEnvVar` is raised.

  # Note: by storing the string in the environment sequence,
  # we gurantee that we don't free the memory before the program
  # ends (this is needed for POSIX compliance). It is also needed so that
  # the process itself may access its modified environment variables!
  var indx = findEnvVar(key)
  if indx >= 0:
    environment[indx] = key & '=' & val
  else:
    add environment, (key & '=' & val)
    indx = high(environment)
  when defined(unix):
    if cputenv(environment[indx]) != 0'i32:
      OSError()
  else:
    if SetEnvironmentVariableA(key, val) == 0'i32:
      OSError()

iterator iterOverEnvironment*(): tuple[key, value: string] =
  ## Iterate over all environments varialbes. In the first component of the
  ## tuple is the name of the current variable stored, in the second its value.
  getEnvVarsC()
  for i in 0..high(environment):
    var p = find(environment[i], '=')
    yield (copy(environment[i], 0, p-1), copy(environment[i], p+1))

iterator walkFiles*(pattern: string): string =
  ## Iterate over all the files that match the `pattern`.
  ##
  ## `pattern` is OS dependant, but at least the "\*.ext"
  ## notation is supported.
  when defined(windows):
    var
      f: TWin32FindData
      res: int
    res = findfirstFileA(pattern, f)
    if res != -1:
      while true:
        if f.cFileName[0] != '.':
          yield extractDir(pattern) / extractFilename($f.cFileName)
        if findnextFileA(res, f) == 0'i32: break
      findclose(res)
  else: # here we use glob
    var
      f: TGlob
      res: int
    f.gl_offs = 0
    f.gl_pathc = 0
    f.gl_pathv = nil
    res = glob(pattern, 0, nil, addr(f))
    if res == 0:
      for i in 0.. f.gl_pathc - 1:
        assert(f.gl_pathv[i] != nil)
        yield $f.gl_pathv[i]
    globfree(addr(f))

type
  TPathComponent* = enum  ## Enumeration specifying a path component.
    pcFile,               ## path refers to a file
    pcLinkToFile,         ## path refers to a symbolic link to a file
    pcDirectory,          ## path refers to a directory
    pcLinkToDirectory     ## path refers to a symbolic link to a directory

iterator walkDir*(dir: string): tuple[kind: TPathComponent, path: string] =
  ## walks over the directory `dir` and yields for each directory or file in
  ## `dir`. The component type and full path for each item is returned.
  ## Walking is not recursive.
  ## Example: Assuming this directory structure::
  ##   dirA / dirB / fileB1.txt
  ##        / dirC
  ##        / fileA1.txt
  ##        / fileA2.txt
  ##
  ## and this code:
  ##
  ## .. code-block:: Nimrod
  ##     for kind, path in walkDir("dirA"):
  ##       echo(path)
  ##
  ## produces this output (though not necessarily in this order!)::
  ##   dirA/dirB
  ##   dirA/dirC
  ##   dirA/fileA1.txt
  ##   dirA/fileA2.txt
  when defined(windows):
    var f: TWIN32_Find_Data
    var h = findfirstFileA(dir / "*", f)
    if h != -1:
      while true:
        var k = pcFile
        if f.cFilename[0] != '.':
          if (f.dwFileAttributes and FILE_ATTRIBUTE_DIRECTORY) != 0'i32:
            k = pcDirectory
          yield (k, dir / extractFilename($f.cFilename))
        if findnextFileA(h, f) == 0'i32: break
      findclose(h)
  else:
    var d = openDir(dir)
    if d != nil:
      while true:
        var x = readDir(d)
        if x == nil: break
        var y = $x.d_name
        if y != "." and y != "..":
          var s: TStat
          y = dir / y
          if stat(y, s) < 0'i32: break
          var k = pcFile
          if S_ISDIR(s.st_mode): k = pcDirectory
          if S_ISLNK(s.st_mode): k = succ(k)
          yield (k, y)
      discard closeDir(d)

proc rawRemoveDir(dir: string) = 
  when defined(windows):
    if RemoveDirectoryA(dir) == 0'i32: OSError()
  else:
    if rmdir(dir) != 0'i32: OSError()

proc removeDir*(dir: string) =
  ## Removes the directory `dir` including all subdirectories or files
  ## in `dir` (recursively). If this fails, `EOS` is raised.
  for kind, path in walkDir(dir): 
    case kind
    of pcFile, pcLinkToFile, pcLinkToDirectory: removeFile(path)
    of pcDirectory: removeDir(dir)
  rawRemoveDir(dir)

proc rawCreateDir(dir: string) =
  when defined(unix):
    if mkdir(dir, 0o711) != 0'i32 and errno != EEXIST:
      OSError()
  else:
    if CreateDirectoryA(dir, nil) == 0'i32 and GetLastError() != 183'i32:
      OSError()

proc createDir*(dir: string) =
  ## Creates the directory `dir`.
  ##
  ## The directory may contain several subdirectories that do not exist yet.
  ## The full path is created. If this fails, `EOS` is raised. It does **not**
  ## fail if the path already exists because for most usages this does not 
  ## indicate an error.
  for i in 1.. dir.len-1:
    if dir[i] in {dirsep, altsep}: rawCreateDir(copy(dir, 0, i-1))
  rawCreateDir(dir)

proc parseCmdLine*(c: string): seq[string] =
  ## Splits a command line into several components; components are separated by
  ## whitespace unless the whitespace occurs within ``"`` or ``'`` quotes. 
  ## This proc is only occassionally useful, better use the `parseopt` module.
  result = @[]
  var i = 0
  var a = ""
  while c[i] != '\0':
    setLen(a, 0)
    while c[i] >= '\1' and c[i] <= ' ': inc(i) # skip whitespace
    case c[i]
    of '\'', '\"':
      var delim = c[i]
      inc(i) # skip ' or "
      while c[i] != '\0' and c[i] != delim:
        add a, c[i]
        inc(i)
      if c[i] != '\0': inc(i)
    else:
      while c[i] > ' ':
        add(a, c[i])
        inc(i)
    add(result, a)

type
  TFilePermission* = enum  ## file access permission; modelled after UNIX
    fpUserExec,            ## execute access for the file owner
    fpUserWrite,           ## write access for the file owner
    fpUserRead,            ## read access for the file owner
    fpGroupExec,           ## execute access for the group
    fpGroupWrite,          ## write access for the group
    fpGroupRead,           ## read access for the group
    fpOthersExec,          ## execute access for others
    fpOthersWrite,         ## write access for others
    fpOthersRead           ## read access for others

proc getFilePermissions*(filename: string): set[TFilePermission] =
  ## retrives file permissions for `filename`. `OSError` is raised in case of
  ## an error. On Windows, only the ``readonly`` flag is checked, every other
  ## permission is available in any case.
  when defined(posix):
    var a: TStat
    if stat(filename, a) < 0'i32: OSError()
    result = {}
    if (a.st_mode and S_IRUSR) != 0'i32: result.incl(fpUserRead)
    if (a.st_mode and S_IWUSR) != 0'i32: result.incl(fpUserWrite)
    if (a.st_mode and S_IXUSR) != 0'i32: result.incl(fpUserExec)

    if (a.st_mode and S_IRGRP) != 0'i32: result.incl(fpGroupRead)
    if (a.st_mode and S_IWGRP) != 0'i32: result.incl(fpGroupWrite)
    if (a.st_mode and S_IXGRP) != 0'i32: result.incl(fpGroupExec)

    if (a.st_mode and S_IROTH) != 0'i32: result.incl(fpOthersRead)
    if (a.st_mode and S_IWOTH) != 0'i32: result.incl(fpOthersWrite)
    if (a.st_mode and S_IXOTH) != 0'i32: result.incl(fpOthersExec)
  else:
    var res = GetFileAttributesA(filename)
    if res == -1'i32: OSError()
    if (res and FILE_ATTRIBUTE_READONLY) != 0'i32:
      result = {fpUserExec, fpUserRead, fpGroupExec, fpGroupRead, 
                fpOthersExec, fpOthersRead}
    else:
      result = {fpUserExec..fpOthersRead}
  
proc setFilePermissions*(filename: string, permissions: set[TFilePermission]) =
  ## sets the file permissions for `filename`. `OSError` is raised in case of
  ## an error. On Windows, only the ``readonly`` flag is changed, depending on
  ## ``fpUserWrite``.
  when defined(posix):
    var p = 0'i32
    if fpUserRead in permissions: p = p or S_IRUSR
    if fpUserWrite in permissions: p = p or S_IWUSR
    if fpUserExec in permissions: p = p or S_IXUSR
    
    if fpGroupRead in permissions: p = p or S_IRGRP
    if fpGroupWrite in permissions: p = p or S_IWGRP
    if fpGroupExec in permissions: p = p or S_IXGRP
    
    if fpOthersRead in permissions: p = p or S_IROTH
    if fpOthersWrite in permissions: p = p or S_IWOTH
    if fpOthersExec in permissions: p = p or S_IXOTH
    
    if chmod(filename, p) != 0: OSError()
  else:
    var res = GetFileAttributesA(filename)
    if res == -1'i32: OSError()
    if fpUserWrite in permissions: 
      res = res and not FILE_ATTRIBUTE_READONLY
    else:
      res = res or FILE_ATTRIBUTE_READONLY
    if SetFileAttributesA(filename, res) != 0'i32: 
      OSError()
  
proc inclFilePermissions*(filename: string, 
                          permissions: set[TFilePermission]) =
  ## a convenience procedure for: 
  ##
  ## .. code-block:: nimrod
  ##   setFilePermissions(filename, getFilePermissions(filename)+permissions)
  setFilePermissions(filename, getFilePermissions(filename)+permissions)

proc exclFilePermissions*(filename: string, 
                          permissions: set[TFilePermission]) =
  ## a convenience procedure for: 
  ##
  ## .. code-block:: nimrod
  ##   setFilePermissions(filename, getFilePermissions(filename)-permissions)
  setFilePermissions(filename, getFilePermissions(filename)-permissions)

proc getHomeDir*(): string =
  ## Returns the home directory of the current user.
  when defined(windows): return getEnv("USERPROFILE") & "\\"
  else: return getEnv("HOME") & "/"

proc getConfigDir*(): string {.noSideEffect.} =
  ## Returns the config directory of the current user for applications.
  when defined(windows): return getEnv("APPDATA") & "\\"
  else: return getEnv("HOME") & "/.config/"

when defined(windows):
  # Since we support GUI applications with Nimrod, we sometimes generate
  # a WinMain entry proc. But a WinMain proc has no access to the parsed
  # command line arguments. The way to get them differs. Thus we parse them
  # ourselves. This has the additional benefit that the program's behaviour
  # is always the same -- independent of the used C compiler.
  var
    ownArgv: seq[string]

  proc paramStr(i: int): string =
    if isNil(ownArgv): ownArgv = parseCmdLine($getCommandLineA())
    return ownArgv[i]

  proc paramCount(): int =
    if isNil(ownArgv): ownArgv = parseCmdLine($getCommandLineA())
    result = ownArgv.len-1

else:
  var
    cmdCount {.importc: "cmdCount".}: cint
    cmdLine {.importc: "cmdLine".}: cstringArray

  proc paramStr(i: int): string =
    if i < cmdCount and i >= 0: return $cmdLine[i]
    raise newException(EInvalidIndex, "invalid index")

  proc paramCount(): int = return cmdCount-1

when defined(linux) or defined(solaris) or defined(bsd) or defined(aix):
  proc getApplAux(procPath: string): string =
    result = newString(256)
    var len = readlink(procPath, result, 256)
    if len > 256:
      result = newString(len+1)
      len = readlink(procPath, result, len)
    setlen(result, len)

when defined(macosx):
  # a really hacky solution: since we like to include 2 headers we have to
  # define two procs which in reality are the same
  proc getExecPath1(c: cstring, size: var int32) {.
    importc: "_NSGetExecutablePath", header: "<sys/param.h>".}
  proc getExecPath2(c: cstring, size: var int32): bool {.
    importc: "_NSGetExecutablePath", header: "<mach-o/dyld.h>".}

proc getApplicationFilename*(): string =
  ## Returns the filename of the application's executable.

  # Linux: /proc/<pid>/exe
  # Solaris:
  # /proc/<pid>/object/a.out (filename only)
  # /proc/<pid>/path/a.out (complete pathname)
  # *BSD (and maybe Darwin too):
  # /proc/<pid>/file
  when defined(windows):
    result = newString(256)
    var len = getModuleFileNameA(0, result, 256)
    setlen(result, int(len))
  elif defined(linux) or defined(aix):
    result = getApplAux("/proc/self/exe")
  elif defined(solaris):
    result = getApplAux("/proc/" & $getpid() & "/path/a.out")
  elif defined(bsd):
    result = getApplAux("/proc/" & $getpid() & "/file")
  elif defined(macosx):
    var size: int32
    getExecPath1(nil, size)
    result = newString(int(size))
    if getExecPath2(result, size):
      result = "" # error!
  else:
    # little heuristic that may work on other POSIX-like systems:
    result = getEnv("_")
    if len(result) == 0:
      result = ParamStr(0) # POSIX guaranties that this contains the executable
                           # as it has been executed by the calling process
      if len(result) > 0 and result[0] != DirSep: # not an absolute path?
        # iterate over any path in the $PATH environment variable
        for p in split(getEnv("PATH"), {PathSep}):
          var x = joinPath(p, result)
          if ExistsFile(x): return x

proc getApplicationDir*(): string =
  ## Returns the directory of the application's executable.
  var tail: string
  splitPath(getApplicationFilename(), result, tail)

{.pop.}