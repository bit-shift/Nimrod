#
#
#            Nimrod's Runtime Library
#        (c) Copyright 2010 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module contains helpers for parsing tokens, numbers, identifiers, etc.

{.deadCodeElim: on.}

{.push debugger:off .} # the user does not want to trace a part
                       # of the standard library!

# copied from excpt.nim, because I don't want to make this template public
template newException(exceptn, message: expr): expr =
  block: # open a new scope
    var
      e: ref exceptn
    new(e)
    e.msg = message
    e

const
  Whitespace = {' ', '\t', '\v', '\r', '\l', '\f'}
  IdentChars = {'a'..'z', 'A'..'Z', '0'..'9', '_'}
  IdentStartChars = {'a'..'z', 'A'..'Z', '_'}
    ## copied from strutils

proc toLower(c: char): char {.inline.} =
  result = if c in {'A'..'Z'}: chr(ord(c)-ord('A')+ord('a')) else: c

proc parseHex*(s: string, number: var int, start = 0): int = 
  ## parses a hexadecimal number and stores its value in ``number``. Returns
  ## the number of the parsed characters or 0 in case of an error.
  var i = start
  var foundDigit = false
  if s[i] == '0' and (s[i+1] == 'x' or s[i+1] == 'X'): inc(i, 2)
  elif s[i] == '#': inc(i)
  while true: 
    case s[i]
    of '_': nil
    of '0'..'9':
      number = number shl 4 or (ord(s[i]) - ord('0'))
      foundDigit = true
    of 'a'..'f':
      number = number shl 4 or (ord(s[i]) - ord('a') + 10)
      foundDigit = true
    of 'A'..'F':
      number = number shl 4 or (ord(s[i]) - ord('A') + 10)
      foundDigit = true
    else: break
    inc(i)
  if foundDigit: result = i-start

proc parseOct*(s: string, number: var int, start = 0): int = 
  ## parses an octal number and stores its value in ``number``. Returns
  ## the number of the parsed characters or 0 in case of an error.
  var i = start
  var foundDigit = false
  if s[i] == '0' and (s[i+1] == 'o' or s[i+1] == 'O'): inc(i, 2)
  while true: 
    case s[i]
    of '_': nil
    of '0'..'7':
      number = number shl 3 or (ord(s[i]) - ord('0'))
      foundDigit = true
    else: break
    inc(i)
  if foundDigit: result = i-start

proc parseIdent*(s: string, ident: var string, start = 0): int =
  ## parses an identifier and stores it in ``ident``. Returns
  ## the number of the parsed characters or 0 in case of an error.
  var i = start
  if s[i] in IdentStartChars:
    inc(i)
    while s[i] in IdentChars: inc(i)
    ident = copy(s, start, i-1)
    result = i-start

proc parseToken*(s: string, token: var string, validChars: set[char],
                 start = 0): int =
  ## parses a token and stores it in ``token``. Returns
  ## the number of the parsed characters or 0 in case of an error. A token
  ## consists of the characters in `validChars`. 
  var i = start
  while s[i] in validChars: inc(i)
  result = i-start
  token = copy(s, start, i-1)

proc skipWhitespace*(s: string, start = 0): int {.inline.} =
  ## skips the whitespace starting at ``s[start]``. Returns the number of
  ## skipped characters.
  while s[start+result] in Whitespace: inc(result)

proc skip*(s, token: string, start = 0): int =
  while result < token.len and s[result+start] == token[result]: inc(result)
  if result != token.len: result = 0
  
proc skipIgnoreCase*(s, token: string, start = 0): int =
  while result < token.len and
      toLower(s[result+start]) == toLower(token[result]): inc(result)
  if result != token.len: result = 0  

{.push overflowChecks: on.}
# this must be compiled with overflow checking turned on:
proc rawParseInt(s: string, b: var biggestInt, start = 0): int =
  var
    sign: BiggestInt = -1
    i = start
  if s[i] == '+': inc(i)
  elif s[i] == '-':
    inc(i)
    sign = 1
  if s[i] in {'0'..'9'}:
    b = 0
    while s[i] in {'0'..'9'}:
      b = b * 10 - (ord(s[i]) - ord('0'))
      inc(i)
      while s[i] == '_': inc(i) # underscores are allowed and ignored
    b = b * sign
    result = i - start
{.pop.} # overflowChecks

proc parseBiggestInt*(s: string, number: var biggestInt, start = 0): int =
  ## parses an integer starting at `start` and stores the value into `number`.
  ## Result is the number of processed chars or 0 if there is no integer.
  ## `EOverflow` is raised if an overflow occurs.
  result = rawParseInt(s, number, start)

proc parseInt*(s: string, number: var int, start = 0): int =
  ## parses an integer starting at `start` and stores the value into `number`.
  ## Result is the number of processed chars or 0 if there is no integer.
  ## `EOverflow` is raised if an overflow occurs.
  var res: biggestInt
  result = parseBiggestInt(s, res, start)
  if (sizeof(int) <= 4) and
      ((res < low(int)) or (res > high(int))):
    raise newException(EOverflow, "overflow")
  else:
    number = int(res)

proc parseBiggestFloat*(s: string, number: var biggestFloat, start = 0): int =
  ## parses a float starting at `start` and stores the value into `number`.
  ## Result is the number of processed chars or 0 if there occured a parsing
  ## error.
  var
    esign = 1.0
    sign = 1.0
    i = start
    exponent: int
    flags: int
  number = 0.0
  if s[i] == '+': inc(i)
  elif s[i] == '-':
    sign = -1.0
    inc(i)
  if s[i] == 'N' or s[i] == 'n':
    if s[i+1] == 'A' or s[i+1] == 'a':
      if s[i+2] == 'N' or s[i+2] == 'n':
        if s[i+3] notin IdentChars:
          number = NaN
          return i+3 - start
    return 0
  if s[i] == 'I' or s[i] == 'i':
    if s[i+1] == 'N' or s[i+1] == 'n':
      if s[i+2] == 'F' or s[i+2] == 'f':
        if s[i+3] notin IdentChars: 
          number = Inf*sign
          return i+3 - start
    return 0
  while s[i] in {'0'..'9'}:
    # Read integer part
    flags = flags or 1
    number = number * 10.0 + toFloat(ord(s[i]) - ord('0'))
    inc(i)
    while s[i] == '_': inc(i)
  # Decimal?
  if s[i] == '.':
    var hd = 1.0
    inc(i)
    while s[i] in {'0'..'9'}:
      # Read fractional part
      flags = flags or 2
      number = number * 10.0 + toFloat(ord(s[i]) - ord('0'))
      hd = hd * 10.0
      inc(i)
      while s[i] == '_': inc(i)
    number = number / hd # this complicated way preserves precision
  # Again, read integer and fractional part
  if flags == 0: return 0
  # Exponent?
  if s[i] in {'e', 'E'}:
    inc(i)
    if s[i] == '+':
      inc(i)
    elif s[i] == '-':
      esign = -1.0
      inc(i)
    if s[i] notin {'0'..'9'}:
      return 0
    while s[i] in {'0'..'9'}:
      exponent = exponent * 10 + ord(s[i]) - ord('0')
      inc(i)
      while s[i] == '_': inc(i)
  # Calculate Exponent
  var hd = 1.0
  for j in 1..exponent: hd = hd * 10.0
  if esign > 0.0: number = number * hd
  else:           number = number / hd
  # evaluate sign
  number = number * sign
  result = i - start

proc parseFloat*(s: string, number: var float, start = 0): int =
  ## parses a float starting at `start` and stores the value into `number`.
  ## Result is the number of processed chars or 0 if there occured a parsing
  ## error.
  var bf: biggestFloat
  result = parseBiggestFloat(s, bf, start)
  number = bf
  
{.pop.}