(* ========================================================================== *)
(*      FPTaylor: A Tool for Rigorous Estimation of Round-off Errors          *)
(*                                                                            *)
(*      Author: Alexey Solovyev, University of Utah                           *)
(*                                                                            *)
(*      This file is distributed under the terms of the MIT license           *)
(* ========================================================================== *)

(* -------------------------------------------------------------------------- *)
(* Optimization with the nlopt library                                        *)
(* -------------------------------------------------------------------------- *)

open Interval
open Expr
open Opt_common

(*
(* nlopt C/C++ code generator *)
type nlopt_pars = {
  nl_alg : int;
  nl_ftol_abs : float;
  nl_ftol_rel : float;
  nl_xtol_abs : float;
  nl_xtol_rel : float;
  nl_maxeval : int;
};;

let nlopt_default = {
  nl_alg = 0;
  nl_ftol_abs = 1e-3;
  nl_ftol_rel = 0.0;
  nl_xtol_abs = 0.0;
  nl_xtol_rel = 0.0;
  nl_maxeval = 20000;
};;
 *)

module Out = ExprOut.Make(ExprOut.CPrinter)

type nlopt_pars = {
  opt : Opt_common.opt_pars;
  nl_alg : int;
}


let gen_nlopt_code (pars : nlopt_pars) fmt =
  let nl = Format.pp_print_newline fmt in
  let p str = Format.pp_print_string fmt str; nl () in

  let head () = 
    p "#include <stdio.h>";
    p "#include <math.h>";
    p "#include <nlopt.h>";
    p "" in

  let gen_nlopt_func vars expr =
    let grad() = () in
    let rec init_vars vs n = 
      match vs with
      | [] -> ()
      | h :: t ->
        p (Format.sprintf "  double var_%s = _x[%d];" (ExprOut.fix_name h) n);
        init_vars t (n + 1) in
    p "double f(unsigned _n, const double *_x, double *_grad, void *_f_data) {";
    init_vars vars 0;
    p "  double _result = ";
    Out.print_fmt fmt expr;
    p ";";
    p "  if (_grad) {";
    grad();
    p "  }";
    p "  return _result;";
    p "}" in

  let str_of_array vs =
    let ss = List.map string_of_float vs in
    "{" ^ String.concat "," ss ^ "}" in

  let options var_bounds =
    let ls, us = List.split (List.map (fun b -> b.low, b.high) var_bounds) in
    let ms = List.map2 (fun l u -> (l +. u) /. 2.0) ls us in
    p "  // Bounds";
    p (Format.sprintf "  nlopt_set_lower_bounds(opt, (double[])%s);" (str_of_array ls));
    p (Format.sprintf "  nlopt_set_upper_bounds(opt, (double[])%s);" (str_of_array us));
    p "  // Stopping criteria";
    p (Format.sprintf "  nlopt_set_ftol_abs(opt, %f);" pars.opt.f_abs_tol);
    p (Format.sprintf "  nlopt_set_maxeval(opt, %d);" pars.opt.max_iters);
    p "  // x0";
    p ("  double x_min[] = " ^ str_of_array ms ^ ";");
    p ("  double x_max[] = " ^ str_of_array ms ^ ";") in

  let main var_names var_bounds =
    p "int main() {";
    p (Format.sprintf "  nlopt_opt opt = nlopt_create(%d, %d);" 
         pars.nl_alg (List.length var_names));
    options var_bounds;
    p "  double f_min = 0.0, f_max = 0.0;";
    p "  // min";
    p "  nlopt_set_min_objective(opt, f, NULL);";
    p "  nlopt_result result_min = nlopt_optimize(opt, x_min, &f_min);";
    p "  // max";
    p "  nlopt_set_max_objective(opt, f, NULL);";
    p "  nlopt_result result_max = nlopt_optimize(opt, x_max, &f_max);";
    p "  printf(\"NLOpt results:\\n\");";
    p "  printf(\"result_min: %d\\n\", result_min);";
    p "  printf(\"result_max: %d\\n\", result_max);";
    p "  printf(\"min: %.20e\\n\", f_min);";
    p "  printf(\"max: %.20e\\n\", f_max);";
    p "  printf(\"x_min: \");";
    p "  for (int i = 0; i < sizeof(x_min) / sizeof(double); i++) { printf(\"%.20e, \", x_min[i]); }";
    p "  printf(\"\\nx_max: \");";
    p "  for (int i = 0; i < sizeof(x_max) / sizeof(double); i++) { printf(\"%.20e, \", x_max[i]); }";
    p "  return 0;";
    p "}" in

  fun (cs, expr) ->
    let var_names = vars_in_expr expr in
    let var_bounds = List.map cs.var_interval var_names in
    head();
    gen_nlopt_func var_names expr;
    main var_names var_bounds


let min_max_expr (pars : Opt_common.opt_pars) (cs : constraints) expr =
  let tmp = Lib.get_tmp_dir () in
  let c_name = Filename.concat tmp "nlopt-f.c" in
  let exe_name = Filename.concat tmp "nlopt-f" in
  let gen = gen_nlopt_code {opt = pars; nl_alg = 0} in
  let _ = Lib.write_to_file c_name gen (cs, expr) in
  let cc = Config.get_string_option "nlopt-cc" in
  let cc_lib = Config.get_string_option "nlopt-lib" in
  let cmd = Format.sprintf "%s -o %s %s %s" cc exe_name c_name cc_lib in
  let out = Lib.run_cmd cmd in
  if out <> [] then
    let str = "Compilation ERROR: " ^ String.concat "\n" (cmd :: out) in
    failwith str
  else
    let out = Lib.run_cmd exe_name in
    Log.report `Debug "%s" (String.concat "\n" out);
    let min = get_float out "min: " and
      max = get_float out "max: " in
    min, max

