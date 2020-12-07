(* ========================================================================== *)
(*      FPTaylor: A Tool for Rigorous Estimation of Round-off Errors          *)
(*                                                                            *)
(*      Author: Alexey Solovyev, University of Utah                           *)
(*                                                                            *)
(*      This file is distributed under the terms of the MIT license           *)
(* ========================================================================== *)

(* -------------------------------------------------------------------------- *)
(* Operations on lists.                                                 *)
(* -------------------------------------------------------------------------- *)

val last : 'a list -> 'a

val insert : 'a -> 'a list -> 'a list

val union : 'a list -> 'a list -> 'a list

val unions : 'a list list -> 'a list

val intersect : 'a list -> 'a list -> 'a list

val subtract : 'a list -> 'a list -> 'a list

val rev_assoc : 'b -> ('a * 'b) list -> 'a

val assoc_eq : ('a -> 'a -> bool) -> 'a -> ('a * 'b) list -> 'b

val assocd : 'b -> 'a -> ('a * 'b) list -> 'b

val assocd_eq : ('a -> 'a -> bool) -> 'b -> 'a -> ('a * 'b) list -> 'b

val (--) : int -> int -> int list

val enumerate : int -> 'a list -> (int * 'a) list

val init_list : int -> (int -> 'a) -> 'a list

(* -------------------------------------------------------------------------- *)
(* Option type operations                                                     *)
(* -------------------------------------------------------------------------- *)

val is_none : 'a option -> bool

val is_some : 'a option -> bool

val option_lift : ('a -> 'b) -> default:'b -> 'a option -> 'b

val option_default : default:'a -> 'a option -> 'a

val option_value : 'a option -> 'a

val option_first : 'a option list -> 'a
                                             
(* -------------------------------------------------------------------------- *)
(* String operations                                                          *)
(* -------------------------------------------------------------------------- *)

val implode : string list -> string

val explode : string -> string list

val print_list : ('a -> unit) -> (unit -> 'b) -> 'a list -> unit

val slice : string -> ?last:int -> first:int -> string

val starts_with : string -> prefix:string -> bool

val concat_env_paths : string list -> string

(* -------------------------------------------------------------------------- *)
(* IO operations.                                                             *)
(* -------------------------------------------------------------------------- *)

val load_and_close_channel : bool -> in_channel -> string list

val load_file : string -> string list

val run_cmd : string -> string list

val write_to_file : string -> (Format.formatter -> 'a -> 'b) -> 'a -> 'b

val write_to_string : (Format.formatter -> 'a -> 'b) -> 'a -> string

val write_to_string_result : (Format.formatter -> 'a -> 'b) -> 'a -> string * 'b

val make_path : ?perm:Unix.file_perm -> string -> unit

val get_dir : string -> string

val set_tmp_dir : string -> unit

val get_tmp_dir : unit -> string
