(* ========================================================================== *)
(*      FPTaylor: A Tool for Rigorous Estimation of Round-off Errors          *)
(*                                                                            *)
(*      Author: Alexey Solovyev, University of Utah                           *)
(*                                                                            *)
(*      This file is distributed under the terms of the MIT license           *)
(* ========================================================================== *)

(* -------------------------------------------------------------------------- *)
(* FPCore output for FPTaylor tasks                                           *)
(* -------------------------------------------------------------------------- *)

open Rounding
open Expr
open Task
open Format

module Out = ExprOut.Make(ExprOut.FPCorePrinter)

let sep fmt str = fun () -> pp_print_string fmt str

let print_formula fmt formula =
  let print_expr = Out.print_fmt ~margin:max_int in
  match formula with
    | Le (a, b) -> fprintf fmt "(<= %a %a)" print_expr a print_expr b
    | Lt (a, b) -> fprintf fmt "(< %a %a)" print_expr a print_expr b
    | Eq (a, b) -> fprintf fmt "(== %a %a)" print_expr a print_expr b

let precision_of_rounding rnd =
  match (rounding_to_string rnd) with
  | "rnd16" -> "binary16"
  | "rnd32" -> "binary32"
  | "rnd64" -> "binary64"
  | "rnd128" -> "binary128"
  | _ -> "real"

(* Selects the most frequent rounding operation type *)
let select_precision expr =
  let table = Hashtbl.create 10 in
  let incr bits =
    let v = 
      try Hashtbl.find table bits with Not_found -> 0 in
    Hashtbl.replace table bits (v + 1) in
  let rec select = function
    | Const c -> ()
    | Var v -> ()
    | U_op (_, arg) -> select arg
    | Bin_op (_, arg1, arg2) -> select arg1; select arg2
    | Gen_op (_, args) -> List.iter select args
    | Rounding (rnd, arg) ->
      incr rnd.fp_type.bits;
      select arg in
  select expr;
  let bits, _ = Hashtbl.fold
      (fun bits v ((_, v_max) as r) ->
         if v >= v_max then (bits, v) else r) 
      table (max_int, 0) in
  create_rounding bits "ne" 1.0

let cmp_rnd r1 r2 =
  r1.fp_type = r2.fp_type && r1.rnd_type = r2.rnd_type

(* Removes all rounding operations corresponding to the given rounding. *)
(* FIXME: this function is not correct for mixed precision computations. *)
let remove_rnd base_rnd expr =
  let rec remove expr =
    match expr with
    | Const c -> expr
    | Var v -> expr
    | U_op (op, arg) -> U_op (op, remove arg)
    | Bin_op (op, arg1, arg2) -> Bin_op (op, remove arg1, remove arg2)
    | Gen_op (op, args) -> Gen_op (op, List.map remove args)
    | Rounding (rnd, arg) ->
      if cmp_rnd base_rnd rnd then remove arg
      else Rounding (rnd, remove arg) in
  remove expr

let var_bounds_to_pre fmt task =
  let print_bounds v =
    let a, b = variable_num_interval task v in
    fprintf fmt "(<= %s %s %s)" (Num.string_of_num a) v (Num.string_of_num b) in
  Lib.print_list print_bounds (sep fmt " ") (all_variables task)

let constraints_to_pre fmt task =
  let formulas = List.map snd task.constraints in
  Lib.print_list (print_formula fmt) (sep fmt " ") formulas

let generate_fpcore fmt task =
  let var_names = all_variables task in
  let prec_rnd, prec = 
    let rnd = select_precision task.expression in
    let prec = precision_of_rounding rnd in
    if prec = "real" then 
      create_rounding max_int "ne" 1.0, prec
    else
      rnd, prec in
  fprintf fmt "(FPCore (%a)@."
    (fun fmt -> Lib.print_list (pp_print_string fmt) (sep fmt " ")) var_names;
  fprintf fmt "  :name \"%s\"@." (String.escaped task.name);
  fprintf fmt "  :description \"Generated by FPTaylor\"@.";
  fprintf fmt "  :precision %s@." prec;
  if task.constraints = [] then
    fprintf fmt "  :pre (and %a)@." var_bounds_to_pre task
  else
    fprintf fmt "  :pre (and %a %a)@."
      var_bounds_to_pre task constraints_to_pre task;
  let expr = remove_rnd prec_rnd task.expression in
  fprintf fmt "  %a)@." (Out.print_fmt ~margin:max_int) expr
