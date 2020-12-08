(* ========================================================================== *)
(*      FPTaylor: A Tool for Rigorous Estimation of Round-off Errors          *)
(*                                                                            *)
(*      Author: Alexey Solovyev, University of Utah                           *)
(*                                                                            *)
(*      This file is distributed under the terms of the MIT license           *)
(* ========================================================================== *)

(* -------------------------------------------------------------------------- *)
(* Optimization with the Z3 SMT solver (see z3opt.py)                         *)
(* -------------------------------------------------------------------------- *)

open Num
open Expr
open Interval
open Opt_common

module Out = ExprOut.Make(ExprOut.Z3PythonPrinter)

let gen_z3py_opt_code (pars : Opt_common.opt_pars) max_only bounds fmt =
  let z3_seed = Config.get_int_option "z3-seed" in
  let nl = Format.pp_print_newline fmt in
  let p str = Format.pp_print_string fmt str; nl() in
  let p' str = 
    Format.pp_print_string fmt str; 
    Format.pp_print_flush fmt () in

  let head () = 
    p "from z3opt import *";
    p "from z3 import *";
    p "" in

  let tail () =
    let max_str = if max_only then "True" else "False" in
    let bounds_str = 
      if Config.get_bool_option "z3-interval-bounds" && More_num.check_interval bounds = "" then
        Format.sprintf "(%.20e, %.20e)" bounds.low bounds.high
      else
        "None" in
    p "";
    p (Format.sprintf
         "l, u = find_bounds(f, var_constraints + constraints, \
          f_abs_tol=%e, f_rel_tol=%e, \
          timeout=%d, seed=%d, max_only=%s, bounds=%s)"
         pars.f_abs_tol pars.f_rel_tol
         pars.timeout z3_seed max_str bounds_str);
    p "print('min = {0:.20e}'.format(l))";
    p "print('max = {0:.20e}'.format(u))" in

  let num_to_z3 n =
    let s = Big_int.string_of_big_int in
    let ns = s (More_num.numerator n) and
      ds = s (More_num.denominator n) in
    (*    "\"" ^ ns ^ "/" ^ ds ^ "\"" in*)
    "Q(" ^ ns ^ "," ^ ds ^ ")" in

  let const_to_z3 c =
    if Const.is_rat c then num_to_z3 (Const.to_num c)
    else failwith "gen_z3py_opt_code: interval constant" in

  let print_constraint c =
    match c with
    | Le (e, Const c) ->
      Out.print_fmt fmt e;
      p' " < ";
      p' (const_to_z3 c)
    | _ -> failwith "z3opt: print_constraint(): unsupported constraint" in

  let constraint_vars c =
    match c with
    | Le (e, Const _) -> vars_in_expr e
    | _ -> failwith "z3opt: constraint_vars(): unsupported constraint" in

  let constraints cs =
    if cs = [] then
      p "constraints = []"
    else
      let _ = p' "constraints = [" in
      let _ = List.map (fun c -> print_constraint c; p' ", ") cs in
      p "]" in

  let vars var_names var_bounds =
    if var_names = [] then 
      p "var_constraints = []"
    else
      let eq_vars, neq_vars = List.partition
          (fun (name, (low, high)) -> low =/ high)
          (List.combine var_names var_bounds) in

      let eqs = List.map
          (fun (name, (low, high)) ->
             Format.sprintf "%s = %s" name (num_to_z3 low))
          eq_vars in
      let constraints = List.map
          (fun (name, (low, high)) ->
             if low =/ high then
               Format.sprintf "%s >= %s, %s <= %s" name (num_to_z3 low) name (num_to_z3 high)
             else
               Format.sprintf "%s >= %s, %s <= %s" name (num_to_z3 low) name (num_to_z3 high))
          neq_vars in
      let names =  String.concat ", " var_names in
      p (Format.sprintf "[%s] = Reals('%s')" names names);
      p (String.concat "\n" eqs);
      p (Format.sprintf "var_constraints = [%s]" (String.concat ", " constraints)) in


(*
      let low, high = unzip var_bounds in
      let low_str = String.concat ", " (map2 (Format.sprintf "%s > %s") 
var_names (map num_to_z3 low)) in
      let high_str = String.concat ", " (map2 (Format.sprintf "%s < %s") 
var_names (map num_to_z3 high)) in
      let names =  String.concat ", " var_names in
      p (Format.sprintf "[%s] = Reals('%s')" names names);
      p (Format.sprintf "var_constraints = [%s, %s]" low_str high_str) in
*)

  let expr e = 
    p' "f = ";
    Out.print_fmt fmt e in

  fun (cs, e) ->
    let vars_cs = List.map constraint_vars cs.constraints in
    let var_names = Lib.unions (vars_in_expr e :: vars_cs) in
    let var_bounds = List.map cs.var_rat_bounds var_names in
    head ();
    vars (List.map (fun name -> "var_" ^ (ExprOut.fix_name name)) var_names) var_bounds;
    constraints cs.constraints;
    expr e;
    tail ()

let name_counter = ref 0;;

let min_max_expr (pars : Opt_common.opt_pars) max_only (cs : constraints) bounds e =
  if vars_in_expr e = [] then
    let n = Eval.eval_num_const_expr e in
    let t = More_num.interval_of_num n in
    (t.low, t.high)
  else
    let tmp = Lib.get_tmp_dir () in
    incr name_counter;
    let py_name = Filename.concat tmp 
        (Format.sprintf "min_max_%d.py" !name_counter) in
    let gen = gen_z3py_opt_code pars max_only bounds in
    let _ = Lib.write_to_file py_name gen (cs, e) in
    let python_path =
      let path = try Unix.getenv "PYTHONPATH" with Not_found -> "" in
      let base = Filename.concat (Config.base_dir ()) "z3opt" in
      let z3path = Config.get_string_option "z3-python-lib" in
      Lib.concat_env_paths [path; base; z3path] in
    let lib_path =
      let path = try Unix.getenv "LD_LIBRARY_PATH" with Not_found -> "" in
      let z3path = Config.get_string_option "z3-bin" in
      Lib.concat_env_paths [path; z3path] in
    let z3python = Config.get_string_option "z3-python-cmd" in
    let cmd = Format.sprintf "LD_LIBRARY_PATH=\"%s\" PYTHONPATH=\"%s\" %s \"%s\""
        lib_path python_path z3python py_name in
    let out = Lib.run_cmd cmd in
    let fmin = Opt_common.get_float out "min = " and
      fmax = Opt_common.get_float out "max = " in
    (fmin, fmax)
