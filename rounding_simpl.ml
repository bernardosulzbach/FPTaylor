(* ========================================================================== *)
(*      FPTaylor: A Tool for Rigorous Estimation of Round-off Errors          *)
(*                                                                            *)
(*      Author: Alexey Solovyev, University of Utah                           *)
(*                                                                            *)
(*      This file is distributed under the terms of the MIT license           *)
(* ========================================================================== *)

(* -------------------------------------------------------------------------- *)
(* Rounding simplification procedures                                         *)
(* -------------------------------------------------------------------------- *)


open Num
open Rounding
open Expr
open Interval
open Binary_float

exception Exceptional_operation of expr * string


let is_power_of_2_or_0 e =
  match e with
  | Const c when Const.is_rat c -> 
    let n = Const.to_num c in
    n =/ Int 0 || More_num.is_power_of_two n
  | _ -> false

let is_neg_power_of_2 e =
  match e with
  | Const c when Const.is_rat c ->
    let n = Const.to_num c in
    if n <>/ Int 0 then
      More_num.is_power_of_two (Int 1 // n)
    else
      false
  | _ -> false

let rec get_type var_type e =
  match e with
  | Const c ->
    if Const.is_rat c then begin
      let n = Const.to_num c in
      (* TODO: a universal procedure is required *)
      let rnd32 = string_to_rounding "rnd32" and
        rnd64 = string_to_rounding "rnd64" in
      if is_exact_fp_const rnd32 n then rnd32.fp_type
      else if is_exact_fp_const rnd64 n then rnd64.fp_type
      else real_type
    end
    else
      real_type
  | Var name -> var_type name
  | U_op (op, arg) ->
    begin
      let arg_type = get_type var_type arg in
      match op with
      | Op_neg | Op_abs -> arg_type
      | _ -> real_type
    end
  | Bin_op (Op_min, arg1, arg2) | Bin_op (Op_max, arg1, arg2) ->
    let ty1 = get_type var_type arg1 and
    ty2 = get_type var_type arg2 in
    if is_subtype ty1 ty2 then ty2
    else if is_subtype ty2 ty1 then ty1
    else real_type
  | Bin_op (Op_mul, arg1, arg2) ->
    if is_power_of_2_or_0 arg1 then 
      get_type var_type arg2
    else if is_power_of_2_or_0 arg2 then
      get_type var_type arg1
    else
      real_type
  | Bin_op (op, arg1, arg2) -> real_type
  | Gen_op _ -> real_type
  | Rounding (rnd, _) -> rnd.fp_type


let simplify_rounding var_type =
  let rec simplify e =
    match e with
    | Const _ -> e
    | Var _ -> e
    | U_op (op, arg) ->
      let e1 = simplify arg in
      U_op (op, e1)
    | Bin_op (op, arg1, arg2) ->
      let e1 = simplify arg1 and
      e2 = simplify arg2 in
      Bin_op (op, e1, e2)
    | Gen_op (op, args) ->
      let es = List.map simplify args in
      Gen_op (op, es)
    | Rounding (rnd, arg) ->
      begin
        let arg = simplify arg in
        let ty = get_type var_type arg in
        if is_no_rnd rnd then
          (* No rounding *)
          arg
        else if is_subtype ty rnd.fp_type then
          (* Rounding is exact *)
          arg
        else
          match arg with
          (* Const *)
          | Const c when Const.is_rat c ->
            if is_exact_fp_const rnd (Const.to_num c) then 
              arg 
            else
              Rounding (rnd, arg)
          (* Plus or minus *)
          | Bin_op (Op_add, e1, e2) | Bin_op (Op_sub, e1, e2) ->
            if is_subtype (get_type var_type e1) rnd.fp_type && 
               is_subtype (get_type var_type e2) rnd.fp_type then
              (* delta = 0 *)
              Rounding ({rnd with delta_exp = 0; special_flag = true;}, arg)
            else
              Rounding (rnd, arg)
          (* Multiplication *)
          | Bin_op (Op_mul, e1, e2) when 
              (is_power_of_2_or_0 e1 && is_subtype (get_type var_type e2) rnd.fp_type) 
              || (is_power_of_2_or_0 e2 && is_subtype (get_type var_type e1) rnd.fp_type) ->
            arg
          | Bin_op (Op_mul, e1, e2) when 
              (is_neg_power_of_2 e1 && is_subtype (get_type var_type e2) rnd.fp_type) 
              || (is_neg_power_of_2 e2 && is_subtype (get_type var_type e1) rnd.fp_type) ->
              Rounding ({rnd with eps_exp = 0}, arg)
          (* Division *)
          | Bin_op (Op_div, e1, e2) when
              is_power_of_2_or_0 e2 && 
              is_subtype (get_type var_type e1) rnd.fp_type ->
            (* eps = 0 *)
            Rounding ({rnd with eps_exp = 0}, arg)
          | Bin_op (Op_div, e1, e2) when
              is_neg_power_of_2 e2 && is_subtype (get_type var_type e1) rnd.fp_type ->
            arg
          (* Square root *)
          | U_op (Op_sqrt, e1) ->
            (* delta = 0 *)
            Rounding ({rnd with delta_exp = 0}, arg)
          | _ -> Rounding (rnd, arg)
      end 
  in
  simplify


(* A very conservative interval rounding *)
let rnd_I rnd x =
  let e = get_eps rnd.eps_exp and
  d = get_eps rnd.delta_exp in
  let ( *^ ) = Fpu.fmul_high and
    ( +^ ) = Fpu.fadd_high and
    ( -^ ) = Fpu.fsub_low in
  let extra v = rnd.coefficient *^ ((e *^ abs_float v) +^ d) in
  let over v = 
    if abs_float v > rnd.max_val then 
      (if v < 0.0 then neg_infinity else infinity)
    else v in
  {
    low = over (x.low -^ extra x.low);
    high = over (x.high +^ extra x.high);
  }

(* A conservative safety check procedure *)
let check_expr vars =
  let rec eval e =
    let r = match e with
      | Const c -> Const.to_interval c
      | Var v -> vars v
      | Rounding (rnd, e1) ->
        let r1 = eval e1 in
        if is_no_rnd rnd then
          r1
        else
          rnd_I rnd r1
      | U_op (op, arg) ->
        begin
          let x = eval arg in
          match op with
          | Op_neg -> ~-$ x
          | Op_abs -> abs_I x
          | Op_inv -> 
            if compare_I_f x 0.0 = 0 then
              raise (Exceptional_operation (e, "Division by zero"))
            else
              inv_I x
          | Op_sqrt -> 
            if x.low < 0.0 then
              raise (Exceptional_operation (e, "Sqrt of negative number"))
            else
              sqrt_I x
          | Op_sin -> sin_I x
          | Op_cos -> cos_I x
          | Op_tan -> tan_I x
          | Op_asin ->
            if x.low < -1.0 || x.high > 1.0 then
              raise (Exceptional_operation (e, "Arcsine of an invalid argument"))
            else
              asin_I x
          | Op_acos ->
            if x.low < -1.0 || x.high > 1.0 then
              raise (Exceptional_operation (e, "Arccosine of an invalid argument"))
            else
              acos_I x
          | Op_atan -> atan_I x
          | Op_exp -> exp_I x
          | Op_log -> 
            if x.low <= 0.0 then
              raise (Exceptional_operation (e, "Log of non-positive number"))
            else
              log_I x
          | Op_sinh -> sinh_I x
          | Op_cosh -> cosh_I x
          | Op_tanh -> tanh_I x
          | Op_asinh -> Func.asinh_I x
          | Op_acosh ->
            if x.low < 1.0 then
              raise (Exceptional_operation (e, "arcosh of x < 1.0"))
            else
              Func.acosh_I x
          | Op_atanh ->
            if x.low <= -1.0 || x.high >= 1.0 then
              raise (Exceptional_operation (e, "artanh of an argument outside of (-1, 1)"))
            else
              Func.atanh_I x
          | Op_floor_power2 -> Func.floor_power2_I x
        end
      | Bin_op (op, arg1, arg2) ->
        begin
          let x1 = eval arg1 in
          match op with
          | Op_add -> x1 +$ eval arg2
          | Op_sub -> x1 -$ eval arg2
          | Op_mul ->
            (* A temporary solution to increase accuracy *)
            if eq_expr arg1 arg2 then
              pow_I_i x1 2
            else
              x1 *$ eval arg2
          | Op_div -> 
            let x2 = eval arg2 in
            if compare_I_f x2 0.0 = 0 then
              raise (Exceptional_operation (e, "Division by zero"))
            else
              x1 /$ x2
          | Op_max -> max_I_I x1 (eval arg2)
          | Op_min -> min_I_I x1 (eval arg2)
          | Op_nat_pow -> x1 **$. (Eval.eval_float_const_expr arg2)
          | _ -> failwith ("check_expr: Unsupported binary operation: " 
                           ^ bin_op_name op)
        end
      | Gen_op (op, args) ->
        begin
          let xs = List.map eval args in
          match (op, xs) with
          | (Op_fma, [a;b;c]) -> (a *$ b) +$ c
          | _ -> failwith ("check_expr: Unsupported general operation: " 
                           ^ gen_op_name op)
        end
    in
    let c = More_num.check_interval r in
    if c <> "" then
      raise (Exceptional_operation (e, c))
    else
      r in
  eval

