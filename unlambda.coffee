# A helper method for using a continuation passing style. Clears the stack when
# CALL_LIMIT continuations have been passed.
CALL_LIMIT = 500
call_current = 0
call = (target, arg) ->
  if call_current >= CALL_LIMIT
    called = 0
    setTimeout (-> target arg), 0
  else
    call_current++
    target arg
  null

# The main evaluation entry point.
#   @arg program: The parsed program to evaluate.
#   @arg result: A callback to which the result of the evaluation is passed.
#   @arg input: A function to call to get input. The function is passed a
#     callback that should be called with the result of the input operation.
#   @arg output: A function to call to print a character.
#   @arg error: A function to call when an error occurs. Equivalent to an
#     exception try/catch handler, but required due to using a continuation
#     passing style of control flow.
runEval = (program, result, input, output, error) ->
  register = undefined

  # Applies a given function to the provided argument and passes the result to
  # the continuation.
  apply = ([func, closure], arg, continuation) ->
    switch func
      when '.'
        output closure
        call continuation, arg
      when 'r'
        output '\n'
        call continuation, arg
      when 'i'
        call continuation, arg
      when 'k'
        call continuation, ['k1', arg]
      when 'k1'
        call continuation, closure
      when 's'
        call continuation, ['s1', arg]
      when 's1'
        call continuation, ['s2', [closure, arg]]
      when 's2'
        [f1, f2] = closure
        apply f1, arg, (r1) ->
          apply f2, arg, (r2) ->
            apply r1, r2, continuation
      when 'v'
        call continuation, ['v', null]
      when 'd1'
        eval ['`', [closure, arg]], (value) ->
          call continuation, value
      when 'e'
        result arg
      when '@'
        input (value_read) ->
          register = value_read?[0]
          action = if register? then 'i' else 'v'
          eval ['`', [arg, [action, null]]], continuation
      when '|'
        if register?
          eval ['`', [arg, ['.', register]]], continuation
        else
          eval ['`', [arg, ['v', null]]], continuation
      when '?'
        action = if register == closure then 'i' else 'v'
        eval ['`', [arg, [action, null]]], continuation
      when 'c'
        eval ['`', [arg, ['c1', continuation]]], continuation
      when 'c1'
        call closure, arg
      else
        error new Error 'Unknown function: ' + func
    null

  # Evaluates an Unlambda node and passes the result to the given continuation.
  eval = ([func, closure], continuation) ->
    if func is '`'
      [func, arg] = closure
      eval func, (evaled_func) ->
        if evaled_func[0] is 'd'
          call continuation, ['d1', arg]
        else
          eval arg, (evaled_arg) ->
            apply evaled_func, evaled_arg, (res) ->
              call continuation, res
    else
      call continuation, [func, closure]
    null

  eval program, (value) -> result value
  null

# Parses a program into an evaluatable Unlambda expression.
#   @arg program: The source code to evaluate.
parse = (program) ->
  doParse = ->
    if program.length is 0 then throw Error 'Unexpected end of input.'
    if program[0] == '`'
      program = program[1..]
      result = ['`', [doParse(), doParse()]]
    else if /^[rksivdce@|]/.test program
      result = [program[0], null]
      program = program[1..]
    else if /^[.?]./.test program
      result = [program[0], program[1]]
      program = program[2..]
    else if match = program.match /^(\s+|#.*)/
      program = program[match[0].length..]
      result = doParse()
    else
      throw new Error 'Invalid character at: ' + program
    result
  doParse()

# Converts a parsed Unlambda expression into a string representation.
#   @arg program:[op, closure]: The Unlambda expression to flatten.
unparse = ([op, closure]) ->
  switch op
    when 'r', 'i', 'k', 's', 'v', 'd', 'c', 'e', '@', '|'
      op
    when 'c1'
      '<cont>'
    when '.', '?'
      op + closure
    when 'k1', 's1', 'd1'
      '`' + op[0] + unparse closure
    when '`'
      '`' + unparse(closure[0]) + unparse(closure[1])
    when 's2'
      '``s' + unparse(closure[0]) + unparse(closure[1])
    else
      throw new Error 'Unparse: unknown function: ' + op

# Exports
@Unlambda =
  parse: parse
  unparse: unparse
  eval: runEval
