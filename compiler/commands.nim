#
#
#           The Nimrod Compiler
#        (c) Copyright 2013 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# This module handles the parsing of command line arguments.

import 
  os, msgs, options, nversion, condsyms, strutils, extccomp, platform, lists, 
  wordrecg, parseutils, babelcmd, idents

proc writeCommandLineUsage*()

type 
  TCmdLinePass* = enum 
    passCmd1,                 # first pass over the command line
    passCmd2,                 # second pass over the command line
    passPP                    # preprocessor called ProcessCommand()

proc ProcessCommand*(switch: string, pass: TCmdLinePass)
proc processSwitch*(switch, arg: string, pass: TCmdlinePass, info: TLineInfo)

# implementation

const
  HelpMessage = "Nimrod Compiler Version $1 (" & compileDate & ") [$2: $3]\n" &
      "Copyright (c) 2004-2013 by Andreas Rumpf\n"

const 
  Usage = slurp"doc/basicopt.txt".replace("//", "")
  AdvancedUsage = slurp"doc/advopt.txt".replace("//", "")

proc getCommandLineDesc(): string = 
  result = (HelpMessage % [VersionAsString, platform.os[platform.hostOS].name, 
                           cpu[platform.hostCPU].name]) & Usage

proc HelpOnError(pass: TCmdLinePass) = 
  if pass == passCmd1:
    MsgWriteln(getCommandLineDesc())
    quit(0)

proc writeAdvancedUsage(pass: TCmdLinePass) = 
  if pass == passCmd1:
    MsgWriteln(`%`(HelpMessage, [VersionAsString, 
                                 platform.os[platform.hostOS].name, 
                                 cpu[platform.hostCPU].name]) & AdvancedUsage)
    quit(0)

proc writeVersionInfo(pass: TCmdLinePass) = 
  if pass == passCmd1:
    MsgWriteln(`%`(HelpMessage, [VersionAsString, 
                                 platform.os[platform.hostOS].name, 
                                 cpu[platform.hostCPU].name]))
    quit(0)

var
  helpWritten: bool

proc writeCommandLineUsage() = 
  if not helpWritten: 
    MsgWriteln(getCommandLineDesc())
    helpWritten = true

proc addPrefix(switch: string): string =
  if len(switch) == 1: result = "-" & switch
  else: result = "--" & switch

proc InvalidCmdLineOption(pass: TCmdLinePass, switch: string, info: TLineInfo) = 
  if switch == " ": LocalError(info, errInvalidCmdLineOption, "-")
  else: LocalError(info, errInvalidCmdLineOption, addPrefix(switch))

proc splitSwitch(switch: string, cmd, arg: var string, pass: TCmdLinePass, 
                 info: TLineInfo) = 
  cmd = ""
  var i = 0
  if i < len(switch) and switch[i] == '-': inc(i)
  if i < len(switch) and switch[i] == '-': inc(i)
  while i < len(switch): 
    case switch[i]
    of 'a'..'z', 'A'..'Z', '0'..'9', '_', '.': add(cmd, switch[i])
    else: break 
    inc(i)
  if i >= len(switch): arg = ""
  elif switch[i] in {':', '=', '['}: arg = substr(switch, i + 1)
  else: InvalidCmdLineOption(pass, switch, info)
  
proc ProcessOnOffSwitch(op: TOptions, arg: string, pass: TCmdlinePass, 
                        info: TLineInfo) = 
  case whichKeyword(arg)
  of wOn: gOptions = gOptions + op
  of wOff: gOptions = gOptions - op
  else: LocalError(info, errOnOrOffExpectedButXFound, arg)
  
proc ProcessOnOffSwitchG(op: TGlobalOptions, arg: string, pass: TCmdlinePass, 
                         info: TLineInfo) = 
  case whichKeyword(arg)
  of wOn: gGlobalOptions = gGlobalOptions + op
  of wOff: gGlobalOptions = gGlobalOptions - op
  else: LocalError(info, errOnOrOffExpectedButXFound, arg)
  
proc ExpectArg(switch, arg: string, pass: TCmdLinePass, info: TLineInfo) = 
  if arg == "": LocalError(info, errCmdLineArgExpected, addPrefix(switch))
  
proc ExpectNoArg(switch, arg: string, pass: TCmdLinePass, info: TLineInfo) = 
  if arg != "": LocalError(info, errCmdLineNoArgExpected, addPrefix(switch))
  
proc ProcessSpecificNote(arg: string, state: TSpecialWord, pass: TCmdlinePass, 
                         info: TLineInfo) = 
  var id = ""  # arg = "X]:on|off"
  var i = 0
  var n = hintMin
  while i < len(arg) and (arg[i] != ']'): 
    add(id, arg[i])
    inc(i)
  if i < len(arg) and (arg[i] == ']'): inc(i)
  else: InvalidCmdLineOption(pass, arg, info)
  if i < len(arg) and (arg[i] in {':', '='}): inc(i)
  else: InvalidCmdLineOption(pass, arg, info)
  if state == wHint: 
    var x = findStr(msgs.HintsToStr, id)
    if x >= 0: n = TNoteKind(x + ord(hintMin))
    else: InvalidCmdLineOption(pass, arg, info)
  else: 
    var x = findStr(msgs.WarningsToStr, id)
    if x >= 0: n = TNoteKind(x + ord(warnMin))
    else: InvalidCmdLineOption(pass, arg, info)
  case whichKeyword(substr(arg, i))
  of wOn: incl(gNotes, n)
  of wOff: excl(gNotes, n)
  else: LocalError(info, errOnOrOffExpectedButXFound, arg)

proc processCompile(filename: string) = 
  var found = findFile(filename)
  if found == "": found = filename
  var trunc = changeFileExt(found, "")
  extccomp.addExternalFileToCompile(found)
  extccomp.addFileToLink(completeCFilePath(trunc, false))

proc testCompileOptionArg*(switch, arg: string, info: TLineInfo): bool =
  case switch.normalize
  of "gc":
    case arg.normalize
    of "boehm":        result = gSelectedGC == gcBoehm
    of "refc":         result = gSelectedGC == gcRefc
    of "v2":           result = gSelectedGC == gcV2
    of "markandsweep": result = gSelectedGC == gcMarkAndSweep
    of "generational": result = gSelectedGC == gcGenerational
    of "none":         result = gSelectedGC == gcNone
    else: LocalError(info, errNoneBoehmRefcExpectedButXFound, arg)
  of "opt":
    case arg.normalize
    of "speed": result = contains(gOptions, optOptimizeSpeed)
    of "size": result = contains(gOptions, optOptimizeSize)
    of "none": result = gOptions * {optOptimizeSpeed, optOptimizeSize} == {}
    else: LocalError(info, errNoneSpeedOrSizeExpectedButXFound, arg)
  else: InvalidCmdLineOption(passCmd1, switch, info)

proc testCompileOption*(switch: string, info: TLineInfo): bool = 
  case switch.normalize
  of "debuginfo": result = contains(gGlobalOptions, optCDebug)
  of "compileonly", "c": result = contains(gGlobalOptions, optCompileOnly)
  of "nolinking": result = contains(gGlobalOptions, optNoLinking)
  of "nomain": result = contains(gGlobalOptions, optNoMain)
  of "forcebuild", "f": result = contains(gGlobalOptions, optForceFullMake)
  of "warnings", "w": result = contains(gOptions, optWarns)
  of "hints": result = contains(gOptions, optHints)
  of "threadanalysis": result = contains(gGlobalOptions, optThreadAnalysis)
  of "stacktrace": result = contains(gOptions, optStackTrace)
  of "linetrace": result = contains(gOptions, optLineTrace)
  of "debugger": result = contains(gOptions, optEndb)
  of "profiler": result = contains(gOptions, optProfiler)
  of "checks", "x": result = gOptions * checksOptions == checksOptions
  of "floatchecks":
    result = gOptions * {optNanCheck, optInfCheck} == {optNanCheck, optInfCheck}
  of "infchecks": result = contains(gOptions, optInfCheck)
  of "nanchecks": result = contains(gOptions, optNanCheck)
  of "objchecks": result = contains(gOptions, optObjCheck)
  of "fieldchecks": result = contains(gOptions, optFieldCheck)
  of "rangechecks": result = contains(gOptions, optRangeCheck)
  of "boundchecks": result = contains(gOptions, optBoundsCheck)
  of "overflowchecks": result = contains(gOptions, optOverflowCheck)
  of "linedir": result = contains(gOptions, optLineDir)
  of "assertions", "a": result = contains(gOptions, optAssert)
  of "deadcodeelim": result = contains(gGlobalOptions, optDeadCodeElim)
  of "run", "r": result = contains(gGlobalOptions, optRun)
  of "symbolfiles": result = contains(gGlobalOptions, optSymbolFiles)
  of "genscript": result = contains(gGlobalOptions, optGenScript)
  of "threads": result = contains(gGlobalOptions, optThreads)
  of "taintmode": result = contains(gGlobalOptions, optTaintMode)
  of "tlsemulation": result = contains(gGlobalOptions, optTlsEmulation)
  of "implicitstatic": result = contains(gOptions, optImplicitStatic)
  of "patterns": result = contains(gOptions, optPatterns)
  else: InvalidCmdLineOption(passCmd1, switch, info)
  
proc processPath(path: string, notRelativeToProj = false): string =
  let p = if notRelativeToProj or os.isAbsolute(path) or
              '$' in path or path[0] == '.': 
            path 
          else:
            options.gProjectPath / path
  result = UnixToNativePath(p % ["nimrod", getPrefixDir(), "lib", libpath,
    "home", removeTrailingDirSep(os.getHomeDir()),
    "projectname", options.gProjectName,
    "projectpath", options.gProjectPath])

proc trackDirty(arg: string, info: TLineInfo) =
  var a = arg.split(',')
  if a.len != 4: LocalError(info, errTokenExpected,
                            "DIRTY_BUFFER,ORIGINAL_FILE,LINE,COLUMN")
  var line, column: int
  if parseUtils.parseInt(a[2], line) <= 0:
    LocalError(info, errInvalidNumber, a[1])
  if parseUtils.parseInt(a[3], column) <= 0:
    LocalError(info, errInvalidNumber, a[2])
  
  gDirtyBufferIdx = a[0].fileInfoIdx
  gDirtyOriginalIdx = a[1].fileInfoIdx
 
  optTrackPos = newLineInfo(gDirtyBufferIdx, line, column)
  msgs.addCheckpoint(optTrackPos)

proc track(arg: string, info: TLineInfo) = 
  var a = arg.split(',')
  if a.len != 3: LocalError(info, errTokenExpected, "FILE,LINE,COLUMN")
  var line, column: int
  if parseUtils.parseInt(a[1], line) <= 0:
    LocalError(info, errInvalidNumber, a[1])
  if parseUtils.parseInt(a[2], column) <= 0:
    LocalError(info, errInvalidNumber, a[2])
  optTrackPos = newLineInfo(a[0], line, column)
  msgs.addCheckpoint(optTrackPos)

proc dynlibOverride(switch, arg: string, pass: TCmdlinePass, info: TLineInfo) =
  if pass in {passCmd2, passPP}:
    expectArg(switch, arg, pass, info)
    options.inclDynlibOverride(arg)

proc processSwitch(switch, arg: string, pass: TCmdlinePass, info: TLineInfo) = 
  var 
    theOS: TSystemOS
    cpu: TSystemCPU
    key, val: string
  case switch.normalize
  of "path", "p": 
    expectArg(switch, arg, pass, info)
    addPath(processPath(arg), info)
  of "babelpath":
    if pass in {passCmd2, passPP}:
      expectArg(switch, arg, pass, info)
      let path = processPath(arg, notRelativeToProj=true)
      babelpath(path, info)
  of "excludepath":
    expectArg(switch, arg, pass, info)
    let path = processPath(arg)
    lists.ExcludeStr(options.searchPaths, path)
    lists.ExcludeStr(options.lazyPaths, path)
  of "nimcache":
    expectArg(switch, arg, pass, info)
    options.nimcacheDir = processPath(arg)
  of "out", "o": 
    expectArg(switch, arg, pass, info)
    options.outFile = arg
  of "mainmodule", "m":
    expectArg(switch, arg, pass, info)
    optMainModule = arg
  of "define", "d": 
    expectArg(switch, arg, pass, info)
    DefineSymbol(arg)
  of "undef", "u": 
    expectArg(switch, arg, pass, info)
    UndefSymbol(arg)
  of "compile": 
    expectArg(switch, arg, pass, info)
    if pass in {passCmd2, passPP}: processCompile(arg)
  of "link": 
    expectArg(switch, arg, pass, info)
    if pass in {passCmd2, passPP}: addFileToLink(arg)
  of "debuginfo": 
    expectNoArg(switch, arg, pass, info)
    incl(gGlobalOptions, optCDebug)
  of "embedsrc":
    expectNoArg(switch, arg, pass, info)
    incl(gGlobalOptions, optEmbedOrigSrc)
  of "compileonly", "c": 
    expectNoArg(switch, arg, pass, info)
    incl(gGlobalOptions, optCompileOnly)
  of "nolinking": 
    expectNoArg(switch, arg, pass, info)
    incl(gGlobalOptions, optNoLinking)
  of "nomain": 
    expectNoArg(switch, arg, pass, info)
    incl(gGlobalOptions, optNoMain)
  of "forcebuild", "f": 
    expectNoArg(switch, arg, pass, info)
    incl(gGlobalOptions, optForceFullMake)
  of "project":
    expectNoArg(switch, arg, pass, info)
    gWholeProject = true
  of "gc": 
    expectArg(switch, arg, pass, info)
    case arg.normalize
    of "boehm": 
      gSelectedGC = gcBoehm
      DefineSymbol("boehmgc")
    of "refc":
      gSelectedGC = gcRefc
    of "v2":
      gSelectedGC = gcV2
    of "markandsweep":
      gSelectedGC = gcMarkAndSweep
      defineSymbol("gcmarkandsweep")
    of "generational":
      gSelectedGC = gcGenerational
      defineSymbol("gcgenerational")
    of "none":
      gSelectedGC = gcNone
      defineSymbol("nogc")
    else: LocalError(info, errNoneBoehmRefcExpectedButXFound, arg)
  of "warnings", "w": ProcessOnOffSwitch({optWarns}, arg, pass, info)
  of "warning": ProcessSpecificNote(arg, wWarning, pass, info)
  of "hint": ProcessSpecificNote(arg, wHint, pass, info)
  of "hints": ProcessOnOffSwitch({optHints}, arg, pass, info)
  of "threadanalysis": ProcessOnOffSwitchG({optThreadAnalysis}, arg, pass, info)
  of "stacktrace": ProcessOnOffSwitch({optStackTrace}, arg, pass, info)
  of "linetrace": ProcessOnOffSwitch({optLineTrace}, arg, pass, info)
  of "debugger": 
    ProcessOnOffSwitch({optEndb}, arg, pass, info)
    if optEndb in gOptions: DefineSymbol("endb")
    else: UndefSymbol("endb")
  of "profiler": 
    ProcessOnOffSwitch({optProfiler}, arg, pass, info)
    if optProfiler in gOptions: DefineSymbol("profiler")
    else: UndefSymbol("profiler")
  of "checks", "x": ProcessOnOffSwitch(checksOptions, arg, pass, info)
  of "floatchecks":
    ProcessOnOffSwitch({optNanCheck, optInfCheck}, arg, pass, info)
  of "infchecks": ProcessOnOffSwitch({optInfCheck}, arg, pass, info)
  of "nanchecks": ProcessOnOffSwitch({optNanCheck}, arg, pass, info)
  of "objchecks": ProcessOnOffSwitch({optObjCheck}, arg, pass, info)
  of "fieldchecks": ProcessOnOffSwitch({optFieldCheck}, arg, pass, info)
  of "rangechecks": ProcessOnOffSwitch({optRangeCheck}, arg, pass, info)
  of "boundchecks": ProcessOnOffSwitch({optBoundsCheck}, arg, pass, info)
  of "overflowchecks": ProcessOnOffSwitch({optOverflowCheck}, arg, pass, info)
  of "linedir": ProcessOnOffSwitch({optLineDir}, arg, pass, info)
  of "assertions", "a": ProcessOnOffSwitch({optAssert}, arg, pass, info)
  of "deadcodeelim": ProcessOnOffSwitchG({optDeadCodeElim}, arg, pass, info)
  of "threads": ProcessOnOffSwitchG({optThreads}, arg, pass, info)
  of "tlsemulation": ProcessOnOffSwitchG({optTlsEmulation}, arg, pass, info)
  of "taintmode": ProcessOnOffSwitchG({optTaintMode}, arg, pass, info)
  of "implicitstatic":
    ProcessOnOffSwitch({optImplicitStatic}, arg, pass, info)
  of "patterns":
    ProcessOnOffSwitch({optPatterns}, arg, pass, info)
  of "opt":
    expectArg(switch, arg, pass, info)
    case arg.normalize
    of "speed": 
      incl(gOptions, optOptimizeSpeed)
      excl(gOptions, optOptimizeSize)
    of "size": 
      excl(gOptions, optOptimizeSpeed)
      incl(gOptions, optOptimizeSize)
    of "none":
      excl(gOptions, optOptimizeSpeed)
      excl(gOptions, optOptimizeSize)
    else: LocalError(info, errNoneSpeedOrSizeExpectedButXFound, arg)
  of "app": 
    expectArg(switch, arg, pass, info)
    case arg.normalize
    of "gui":
      incl(gGlobalOptions, optGenGuiApp)
      defineSymbol("executable")
      defineSymbol("guiapp")
    of "console":
      excl(gGlobalOptions, optGenGuiApp)
      defineSymbol("executable")
      defineSymbol("consoleapp")
    of "lib":
      incl(gGlobalOptions, optGenDynLib)
      excl(gGlobalOptions, optGenGuiApp)
      defineSymbol("library")
      defineSymbol("dll")
    of "staticlib":
      incl(gGlobalOptions, optGenStaticLib)
      excl(gGlobalOptions, optGenGuiApp)
      defineSymbol("library")
      defineSymbol("staticlib")
    else: LocalError(info, errGuiConsoleOrLibExpectedButXFound, arg)
  of "passc", "t": 
    expectArg(switch, arg, pass, info)
    if pass in {passCmd2, passPP}: extccomp.addCompileOption(arg)
  of "passl", "l": 
    expectArg(switch, arg, pass, info)
    if pass in {passCmd2, passPP}: extccomp.addLinkOption(arg)
  of "cincludes":
    expectArg(switch, arg, pass, info)
    if pass in {passCmd2, passPP}: cIncludes.add arg
  of "clibdir":
    expectArg(switch, arg, pass, info)
    if pass in {passCmd2, passPP}: cLibs.add arg
  of "clib":
    expectArg(switch, arg, pass, info)
    if pass in {passCmd2, passPP}: cLinkedLibs.add arg
  of "header":
    headerFile = arg
    incl(gGlobalOptions, optGenIndex)
  of "index":
    ProcessOnOffSwitchG({optGenIndex}, arg, pass, info)
  of "import":
    expectArg(switch, arg, pass, info)
    if pass in {passCmd2, passPP}: implicitImports.add arg
  of "include":
    expectArg(switch, arg, pass, info)
    if pass in {passCmd2, passPP}: implicitIncludes.add arg
  of "listcmd": 
    expectNoArg(switch, arg, pass, info)
    incl(gGlobalOptions, optListCmd)
  of "genmapping": 
    expectNoArg(switch, arg, pass, info)
    incl(gGlobalOptions, optGenMapping)
  of "os": 
    expectArg(switch, arg, pass, info)
    if pass in {passCmd1, passPP}: 
      theOS = platform.NameToOS(arg)
      if theOS == osNone: LocalError(info, errUnknownOS, arg)
      elif theOS != platform.hostOS: 
        setTarget(theOS, targetCPU)
        condsyms.InitDefines()
  of "cpu": 
    expectArg(switch, arg, pass, info)
    if pass in {passCmd1, passPP}: 
      cpu = platform.NameToCPU(arg)
      if cpu == cpuNone: LocalError(info, errUnknownCPU, arg)
      elif cpu != platform.hostCPU: 
        setTarget(targetOS, cpu)
        condsyms.InitDefines()
  of "run", "r": 
    expectNoArg(switch, arg, pass, info)
    incl(gGlobalOptions, optRun)
  of "verbosity": 
    expectArg(switch, arg, pass, info)
    gVerbosity = parseInt(arg)
  of "parallelbuild": 
    expectArg(switch, arg, pass, info)
    gNumberOfProcessors = parseInt(arg)
  of "version", "v": 
    expectNoArg(switch, arg, pass, info)
    writeVersionInfo(pass)
  of "advanced": 
    expectNoArg(switch, arg, pass, info)
    writeAdvancedUsage(pass)
  of "help", "h": 
    expectNoArg(switch, arg, pass, info)
    helpOnError(pass)
  of "symbolfiles": 
    ProcessOnOffSwitchG({optSymbolFiles}, arg, pass, info)
  of "skipcfg": 
    expectNoArg(switch, arg, pass, info)
    incl(gGlobalOptions, optSkipConfigFile)
  of "skipprojcfg": 
    expectNoArg(switch, arg, pass, info)
    incl(gGlobalOptions, optSkipProjConfigFile)
  of "skipusercfg":
    expectNoArg(switch, arg, pass, info)
    incl(gGlobalOptions, optSkipUserConfigFile)
  of "skipparentcfg":
    expectNoArg(switch, arg, pass, info)
    incl(gGlobalOptions, optSkipParentConfigFiles)
  of "genscript": 
    expectNoArg(switch, arg, pass, info)
    incl(gGlobalOptions, optGenScript)
  of "lib":
    expectArg(switch, arg, pass, info)
    libpath = processPath(arg, notRelativeToProj=true)
  of "putenv": 
    expectArg(switch, arg, pass, info)
    splitSwitch(arg, key, val, pass, info)
    os.putEnv(key, val)
  of "cc": 
    expectArg(switch, arg, pass, info)
    setCC(arg)
  of "track":
    expectArg(switch, arg, pass, info)
    track(arg, info)
  of "trackdirty":
    expectArg(switch, arg, pass, info)
    trackDirty(arg, info)
  of "suggest": 
    expectNoArg(switch, arg, pass, info)
    incl(gGlobalOptions, optSuggest)
  of "def":
    expectNoArg(switch, arg, pass, info)
    incl(gGlobalOptions, optDef)
  of "eval":
    expectArg(switch, arg, pass, info)
    gEvalExpr = arg
  of "context":
    expectNoArg(switch, arg, pass, info)
    incl(gGlobalOptions, optContext)
  of "usages":
    expectNoArg(switch, arg, pass, info)
    incl(gGlobalOptions, optUsages)
  of "stdout":
    expectNoArg(switch, arg, pass, info)
    incl(gGlobalOptions, optStdout)
  of "listfullpaths":
    expectNoArg(switch, arg, pass, info)
    gListFullPaths = true
  of "dynliboverride":
    dynlibOverride(switch, arg, pass, info)
  of "cs":
    expectArg(switch, arg, pass, info)
    case arg
    of "partial": idents.firstCharIsCS = true
    of "none": idents.firstCharIsCS = false
    else: LocalError(info, errGenerated,
      "'partial' or 'none' expected, but found " & arg)
  else:
    if strutils.find(switch, '.') >= 0: options.setConfigVar(switch, arg)
    else: InvalidCmdLineOption(pass, switch, info)
  
proc ProcessCommand(switch: string, pass: TCmdLinePass) =
  var cmd, arg: string
  splitSwitch(switch, cmd, arg, pass, gCmdLineInfo)
  processSwitch(cmd, arg, pass, gCmdLineInfo)
