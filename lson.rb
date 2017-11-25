require 'json'
require 'readline'

module AL
  module_function

  def has_key?(al, key)
    pair = al.assoc(key)
    return !!pair
  end

  def lookup(al, key)
    pair = al.assoc(key)
    if pair
      pair[1]
    else
      nil
    end
  end
end

class Evaluator
  def initialize
    @global_env = [
      *[">=", ">", "==", "!=", "<", "<=",
        "+", "-", "*", "/", "list", "p", "globals",
        "append","conj","cons"].map { |f| [f, ["builtin", f]] }
    ]
    @macros = [
      ["let", ["builtin", "let"]]
    ]
    eval(["defmacro", "defun", ["name","params","&","body"],
          ["list", ["","do"],
           ["list", ["","def"], "name",
            ["append", ["list", ["","fn"], "params"], "body"]],
           ["list", ["",""],"name"]]], [])
    eval(["defun", "not", ["x"], ["if", "x", false, true]], [])
  end

  def apply_builtin_function(name, args)
    case name
    when "+", "-", "*", "/"
      args.inject(name)
    when ">=", ">", "==", "!=", "<", "<="
      fail '2 or more arguments expected' unless args.size >= 2
      args.each_cons(2).all? { |x,y| x.__send__(name, y) }
    when "list"
      args
    when "let"
      vars, vals = args[0].each_slice(2).to_a.transpose
      [["fn", vars, *args[1..-1]], *vals]
    when "p"
      p(*args)
    when "globals"
      @global_env.map(&:first)
    when "append"
      fail "type error" unless args.all? { |a| a.is_a?(Array) }
      args.inject([], :+)
    when "conj"
      fail "too few arguments" unless args.size >= 2
      fail "type error" unless args[0].is_a?(Array)
      args[0] + args[1..-1]
    when "cons"
      fail "wrong # of arguments" unless args.size == 2
      fail "type error" unless args[1].is_a?(Array)
      [args[0]] + args[1]
    else
      fail "undefined builtin #{name.inspect}"
    end
  end

  def make_bindings(params, args)
    if params.empty?
      fail "too many arguments" if args.size > 0
      return []
    else
      first, *rest = params

      case first
      when "&" # 可変長引数
        fail "no name after &" if rest.size < 1
        fail "too many names after &" if rest.size > 1
        name = rest[0]
        return [[name, args]]
      when String
        fail "too few arguments" unless args.size > 0
        return [[first, args[0]]] + make_bindings(rest, args[1..-1])
      when Array
        unless args.size > 0 && args[0].is_a?(Array)
          fail "cannot undestructure a non-array type #{args[0].inspect}"
        end
        return make_bindings(first, args[0]) + make_bindings(rest, args[1..-1])
      end
    end
  end

  # args は評価済み。
  def apply_function(function, args)
    case function
    when Hash
      fail "wrong # of arguments" unless args.size >= 1
      fail "invalid key type" unless args[0].is_a?(String)
      function[args[0]]
    when Array
      case function[0]
      when "closure"
        _, fn_form, saved_env = function
        _, params, *body = fn_form
        fenv = make_bindings(params, args) + saved_env
        body.map { |e|
          eval(e, fenv)
        }.last
      when "builtin"
        _, name1 = function
        apply_builtin_function(name1, args)
      else
        fail "not a function #{function.inspect}"
      end
    else
      fail "not a function #{function.inspect}"
    end
  end

  def eval_form(form, env)
    name, *args = form
    case name
    when "quote", ""
      fail "no arguments to quote" unless args.size > 0
      if args.size == 1
        args[0]
      else
        args
      end
    when "def" # グローバル変数を定義する
      fail "def requires 2 args" unless args.size == 2
      fail "type error" unless args[0].is_a? String
      if AL.has_key?(@global_env, args[0])
        fail "#{args[0].inspect} already defined"
      else
        eval(args[1], env).tap do |value|
          @global_env.unshift [args[0], value]
        end
      end
    when "if"
      fail 'invalid if form' unless args.size.between?(2,3)
      test, then_clause, else_clause = args
      if eval(test, env)
        eval(then_clause, env)
      else
        (args.size == 3) ? eval(else_clause, env) : nil
      end
    when "fn"
      # ["closure", ["fn",["x"],["+",1,"x"]], [環境...]]
      ["closure", form, env]
    when "defmacro"
      name, params, *body = args
      fail "name" unless name.is_a? String
      fail "params" unless params.is_a? Array
      if AL.has_key?(@macros, name)
        fail "macro #{name} already defined"
      end
      fn = eval(["fn", params, *body], env)
      @macros.unshift [name, fn]
      name
    when "do"
      args.map { |a| eval(a, env) }.last
    else
      if AL.lookup(@macros, name)
        expansion = apply_function(AL.lookup(@macros, name), args)
        eval(expansion, env)
      else
        apply_function(eval(name, env), args.map { |a| eval(a, env) })
      end
    end
  end

  def eval(exp, env)
    case exp
    when Numeric then exp
    when String
      if AL.has_key?(env, exp)
        AL.lookup(env, exp)
      elsif AL.has_key?(@global_env, exp)
        AL.lookup(@global_env, exp)
      else
        fail "unbound name #{exp.inspect}"
      end
    when Array
      if exp == []
        []
      else
        eval_form(exp, env)
      end
    when Hash
      exp.map { |k,v| [k,eval(v, env)] }.to_h
    else
      exp
    end
  end
end

PS1 = "> "
def repl
  puts "LSON"
  evaluator = Evaluator.new
  loop do
    line = Readline.readline(PS1, true)
    begin
      data = JSON.parse(line)
      result = evaluator.eval(data, [])
      puts JSON.dump(result)
    rescue => e
      puts "Error: #{e}"
      puts e.backtrace
    end
  end
end

if __FILE__ == $0
  repl
end
