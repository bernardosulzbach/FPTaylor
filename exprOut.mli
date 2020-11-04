(* ========================================================================== *)
(*      FPTaylor: A Tool for Rigorous Estimation of Round-off Errors          *)
(*                                                                            *)
(*      Author: Alexey Solovyev, University of Utah                           *)
(*                                                                            *)
(*      This file is distributed under the terms of the MIT license           *)
(* ========================================================================== *)

(* -------------------------------------------------------------------------- *)
(* Symbolic expression printing                                               *)
(* -------------------------------------------------------------------------- *)

module type PrinterType

val fix_name : string -> string

module type P =
  sig
    val print_fmt : ?margin:int -> Format.formatter -> Expr.expr -> unit
    val print_std : ?margin:int -> Expr.expr -> unit
    val print_str : ?margin:int -> Expr.expr -> string
  end

module Make (Printer : PrinterType) : P

module OCamlIntervalPrinter : PrinterType

module FPCorePrinter : PrinterType

module RacketIntervalPrinter : PrinterType

module CPrinter : PrinterType

module OCamlFloatPrinter : PrinterType

module Z3PythonPrinter : PrinterType

module GelpiaPrinter : PrinterType

module JavaScriptPrinter : PrinterType

module JavaScriptIntervalPrinter : PrinterType

module Info : P
