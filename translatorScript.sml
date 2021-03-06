open preamble;

open bitstringSyntax boolSyntax combinSyntax numSyntax stringSyntax;
open arithmeticTheory bitstringTheory indexedListsTheory optionTheory wordsTheory wordsSyntax;

open dep_rewrite;

open wordsLib;

open verilogTheory verilogMetaTheory verilogSyntax;
open translatorCoreTheory translatorCoreLib;
open tinyConfigLib tinyMachineTheory tinyImplTheory;

val _ = new_theory "translator";

(** State vars **)

local
  val svs = map (fromMLstring o fst) (TypeBase.fields_of state_ty)
            |> (listSyntax.mk_list |> curry |> flip) string_ty
in
val state_var_def = Define `state_var name = MEM name ^svs`;
end;

(** relS **)

val relS_var_def = Define `
 relS_var hol_s (ver_s:pstate) var a accessf =
  (?v. get_var ver_s var = INR v /\ a (accessf hol_s) v)`;

fun build_relS_var (name, accessf) = let
  val nameHOL = fromMLstring name
  val pred = accessf |> dest_const |> snd |> dom_rng |> snd |> predicate_for_type_ty
in
  ``relS_var hol_s ver_s ^nameHOL ^pred ^accessf``
end;

val relS_def =
 accessors
 |> map build_relS_var
 |> list_mk_conj
(* |> (curry mk_conj) ``ver_s.nbq = []`` <-- can be added by computation afterwards *)
(* UGLY: *)
(* |> (curry mk_icomb) (mk_icomb (equality, mk_comb (mk_comb (mk_var ("relS", ``:tinyImpl_state -> pstate -> bool``), mk_var ("hol_s", ``:tinyImpl_state``)), mk_var ("ver_s", ``:pstate``))))
 |> (curry new_definition) "relS";
*)
 |> (fn tm => Define `relS hol_s ver_s = ^tm`);

(*
val relS_var_s_irrelevant = Q.store_thm("relS_var_s_irrelevant",
 `!s env ver_s ver_s'. relS s (ver_s with vars := env) = relS s (ver_s' with vars := env)`,
 rw [relS_def, relS_var_def, get_var_def]);

val relS_with_vars_cleanup = Q.store_thm("relS_with_vars_cleanup",
 `!ver_s ver_s' s. relS s (ver_s with vars := ver_s'.vars) = relS s (ver_s')`,
  rw [relS_def, relS_var_def, get_var_def]);
*)

(* Eval for pure expressions, i.e. erun *)

val Eval_def = Define `
 Eval s env P exp =
   !ver_s. relS s (ver_s with vars := env) ==>
   ?res. erun (ver_s with vars := env) exp = INR res /\ P res`;

val var_has_value_def = Define `
 var_has_value (env:envT) var P = ?v. ALOOKUP env var = SOME v /\ P v`;

val var_has_type_def = Define `
 var_has_type env var P = ?hrep. var_has_value env var (P hrep)`;

val var_has_value_imp_var_has_type = Q.store_thm("var_has_value_imp_var_has_type",
 `!var v a env. var_has_value env var (a v) ==> var_has_type env var a`,
 metis_tac [var_has_type_def, var_has_value_def]);

(* The verilog program vp transforms state in the same way as the hol program hp,
   same as Eval but for pure code (non-monadic export, i.e. state visible in predicate, not just an argument to function) *)
val EvalS_def = Define `
  EvalS s env (hp : tinyImpl_state) vp =
    !ver_s.
     relS s (ver_s with vars := env)
     ==> ?ver_s'. (prun (ver_s with vars := env) vp = INR (NONE, ver_s')) /\
                  relS hp ver_s'`;

(** relS and prun things **)

(* TOOD: Can be expressed as set_var instead? *)
val relS_not_state_var = Q.store_thm("relS_not_state_var",
 `!hol_s ver_s env name v.
   relS hol_s (ver_s with vars := env) /\ ~state_var name ==>
   relS hol_s (ver_s with vars := (name, v) :: env)`,
 rw [state_var_def, relS_def, relS_var_def, get_var_def]);

(* TODO: Better name cmp to above? *)
val relS_not_state_var_remove = Q.store_thm("relS_not_state_var_remove",
 `!hol_s ver_s env name v.
   relS hol_s (ver_s with vars := (name, v) :: env) /\ ~state_var name ==>
   relS hol_s (ver_s with vars := env)`,
 rw [state_var_def, relS_def, relS_var_def] \\ fs [get_var_def]);

val pstate_vars_cleanup = Q.store_thm("pstate_vars_cleanup",
 `!(s:pstate). (s with vars := s.vars) = s`,
 rw [pstate_component_equality]);

(** same_shape thms **)

val EXP_n_lt_2n = Q.store_thm("EXP_n_lt_2n",
 `!n. n < 2 ** n`,
 Induct \\ rw [arithmeticTheory.EXP]);

val same_shape_VArray_from_v = Q.store_thm("same_shape_VArray_from_v",
 `!v1 v2. LENGTH v1 = LENGTH v2 ==> same_shape (VArray (MAP VBool v1)) (VArray (MAP VBool v2))`,
 Induct \\ rw [same_shape_def] \\ Cases_on `v2` \\ fs [same_shape_def]);

val same_shape_LENGTH = Q.store_thm("same_shape_LENGTH",
 `!xs ys. same_shape (VArray xs) (VArray ys) ==> LENGTH xs = LENGTH ys`,
 Induct \\ Cases_on `ys` \\ rw [same_shape_def]);

val same_shape_APPEND = Q.store_thm("same_shape_APPEND",
 `!xs x ys y.
   same_shape (VArray xs) (VArray ys) /\ same_shape x y ==>
   same_shape (VArray (xs ++ [x])) (VArray (ys ++ [y]))`,
 Induct \\ Cases_on `ys` \\ rw [same_shape_def]);

val same_shape_VArray_cong = Q.store_thm("same_shape_VArray_cong",
 `!l l'.
   (!n. n < LENGTH l ==> ?ln l'n. sum_revEL n l = INR ln /\ sum_revEL n l' = INR l'n /\ same_shape ln l'n) /\
   LENGTH l = LENGTH l' ==>
   same_shape (VArray l) (VArray l')`,
 Induct \\ Cases_on `l'` \\ rw [same_shape_def]
 >- (first_x_assum (qspec_then `LENGTH l` mp_tac) \\ impl_tac >- DECIDE_TAC \\ fs [sum_revEL_LENGTH])
 \\ first_x_assum match_mp_tac \\ rpt strip_tac \\ fs [] \\
    first_x_assum (qspec_then `n` mp_tac) \\ impl_tac >- DECIDE_TAC \\ metis_tac [sum_revEL_INR_LENGTH]);

val same_shape_VArray_sum_revEL_cong = Q.store_thm("same_shape_VArray_sum_revEL_cong",
 `!l l' n.
   (!(i:'a word). ?lsub. LENGTH lsub = n /\ sum_revEL (w2n i) l = INR (VArray (MAP VBool lsub))) /\
   (!(i:'a word). ?l'sub. LENGTH l'sub = n /\ sum_revEL (w2n i) l' = INR (VArray (MAP VBool l'sub))) /\
   LENGTH l = dimword (:'a) /\
   LENGTH l' = dimword (:'a) ==>
   same_shape (VArray l) (VArray l')`,
 rpt strip_tac \\ match_mp_tac same_shape_VArray_cong \\ rpt strip_tac \\ fs [] \\
 rpt (first_x_assum (qspec_then `n2w n':'a word` assume_tac)) \\
 fs [w2n_n2w] \\ rpt strip_tac \\
 `n' < dimword (:'a)` by metis_tac [dimword_def, EXP_n_lt_2n, arithmeticTheory.LESS_TRANS] \\
 fs [arithmeticTheory.LESS_MOD] \\ match_mp_tac same_shape_VArray_from_v \\ fs []);

val same_shape_w2ver = Q.store_thm("same_shape_w2ver",
 `!(w1:'a word) (w2:'a word). same_shape (w2ver w1) (w2ver w2)`,
 rw [w2ver_def, same_shape_VArray_from_v]);

val same_shape_BOOL = Q.store_thm("same_shape_BOOL",
 `!b1 v1 b2 v2. BOOL b1 v1 /\ BOOL b2 v2 ==> same_shape v1 v2`,
 rw [BOOL_def, same_shape_def]);

val same_shape_WORD = Q.store_thm("same_shape_WORD",
 `!w1 v1 w2 v2. WORD (w1:'a word) v1 /\ WORD (w2:'a word) v2 ==> same_shape v1 v2`,
 rw [WORD_def, w2ver_def, same_shape_VArray_from_v]);

val same_shape_WORD_ARRAY = Q.store_thm("same_shape_WORD_ARRAY",
 `!(w1:'a word -> 'b word) v1 (w2:'a word -> 'b word) v2.
   WORD_ARRAY w1 v1 /\ WORD_ARRAY w2 v2 ==> same_shape v1 v2`,
 rw [WORD_ARRAY_def, w2ver_def] \\ Cases_on `v1` \\ Cases_on `v2` \\ fs [] \\
 match_mp_tac same_shape_VArray_sum_revEL_cong \\ qexists_tac `dimindex (:'b)` \\
 metis_tac [length_w2v]);

(* Simple meta-theory for blocking assignments, essentially same_shape glue *)
val prun_bassn_works_WORD = Q.store_thm("prun_bassn_works_WORD",
 `!s (w1:'a word) vnew (w2:'a word) vold var.
   WORD w1 vnew /\
   get_var s var = INR vold /\
   WORD w2 vold ==>
   prun_bassn s (Var var) vnew = INR (NONE:value option, set_var s var vnew)`,
 rpt strip_tac \\ simp [prun_bassn_def, assn_def, sum_bind_def] \\
 (* UGLY: Want to split directly on if in some sense, know its true... *)
 REVERSE TOP_CASE_TAC >- metis_tac [same_shape_WORD] \\
 simp [sum_for_def, sum_map_def]);

val prun_bassn_works_BOOL = Q.store_thm("prun_bassn_works_BOOL",
 `!s b1 vnew b2 vold var.
   BOOL b1 vnew /\
   get_var s var = INR vold /\
   BOOL b2 vold ==>
   prun_bassn s (Var var) vnew = INR (NONE:value option, set_var s var vnew)`,
 rpt strip_tac \\ simp [prun_bassn_def, assn_def, sum_bind_def] \\
 (* UGLY: Want to split directly on if in some sense, know its true... *)
 REVERSE TOP_CASE_TAC >- metis_tac [same_shape_BOOL] \\
 simp [sum_for_def, sum_map_def]);

(** prun_bassn_type_pred things, used in e.g. EvalS_Let **)

(* TODO: Can make this an inductive predicate instead?
         Not obvious at least... could introduce type system... *)
val prun_bassn_type_pred_def = Define `
 prun_bassn_type_pred (type_pred : 'a -> value -> bool) =
  !env s ver_s (name : string) (arg : 'a) (oldv : value) (newv : value).
   relS s (ver_s with vars := env) /\
   var_has_type env name type_pred /\
   type_pred arg newv
   ==>
   prun_bassn (ver_s with vars := env) (Var name) newv = INR (NONE:value option,
                                                              ver_s with vars := (name, newv) :: env)`;

val prun_bassn_type_pred_ALL = Q.store_thm("prun_bassn_type_pred_ALL",
 `prun_bassn_type_pred BOOL /\ prun_bassn_type_pred WORD /\ prun_bassn_type_pred WORD_ARRAY`,
 rpt CONJ_TAC \\
 rw [prun_bassn_type_pred_def, var_has_type_def, var_has_value_def, get_var_def,
     Eval_def, erun_def, prun_bassn_def, assn_def] \\
 res_tac \\

 imp_res_tac same_shape_BOOL \\
 imp_res_tac same_shape_WORD \\
 imp_res_tac same_shape_WORD_ARRAY \\

 fs [set_var_def, sum_bind_def, sum_for_def, sum_map_def]);

val prun_bassn_type_pred_BOOL = Q.store_thm("prun_bassn_type_pred_BOOL",
 `prun_bassn_type_pred BOOL`,
 rw [prun_bassn_type_pred_ALL]);

val prun_bassn_type_pred_WORD = Q.store_thm("prun_bassn_type_pred_WORD",
 `prun_bassn_type_pred WORD`,
 rw [prun_bassn_type_pred_ALL]);

val prun_bassn_type_pred_WORD_ARRAY = Q.store_thm("prun_bassn_type_pred_WORD_ARRAY",
 `prun_bassn_type_pred WORD_ARRAY`,
  rw [prun_bassn_type_pred_ALL]);

(** Eval thms and hol2hardware_exp **)

val var_thm_BOOL = Q.store_thm("var_thm_BOOL",
 `!s b var. var_has_value env var (BOOL b) ==> Eval s env (BOOL b) (Var var)`,
 rw [var_has_value_def, Eval_def, erun_def, get_var_def] \\ rw []);

val var_thm_WORD = Q.store_thm("var_thm_WORD",
 `!s w var. var_has_value env var (WORD w) ==> Eval s env (WORD w) (Var var)`,
 rw [var_has_value_def, Eval_def, erun_def, get_var_def] \\ rw []);

(* TODO: Rename to something more descriptive? *)
val Eval_Var_WORD = Q.store_thm("Eval_Var_WORD",
 `!s ver_s env x xname.
   relS s (ver_s with vars := env) /\
   Eval s env (WORD x) (Var xname) ==>
   get_var (ver_s with vars := env) xname = INR (w2ver x)`,
 rw [Eval_def, erun_def, WORD_def] \\ res_tac);

val Eval_bool = Q.store_thm("Eval_bool",
 `!b s. Eval s env (BOOL b) (Const (VBool b))`,
 rw [Eval_def, erun_def, BOOL_def]);

(* Need to go through n -> w -> ver because we need to truncate the word in the same way as LHS *)
val Eval_word_const = Q.store_thm("Eval_word_const",
 `!s n. Eval s env (WORD ((n2w n) : 'a word)) (Const (w2ver ((n2w n) : 'a word)))`,
  rw [Eval_def, WORD_def, erun_def, w2ver_def]);

(* There's just one BUOp case *)
val Eval_BOOL_Not = Q.store_thm("Eval_BOOL_Not",
 `!s b v. Eval s env (BOOL b) v ==> Eval s env (BOOL (~b)) (BUOp Not v)`,
 rw [Eval_def, erun_def, BOOL_def, sum_bind_def, ver_liftVBool_def]);

val Eval_BOOL_bbop = Q.store_thm("Eval_BOOL_bbop",
 `!s b1 v1 b2 v2.
   Eval s env (BOOL b1) v1 /\
   Eval s env (BOOL b2) v2 ==>
   Eval s env (BOOL (b1 /\ b2)) (BBOp v1 And v2) /\
   Eval s env (BOOL (b1 = b2)) (BBOp v1 Equal v2) /\
   Eval s env (BOOL (b1 <> b2)) (BBOp v1 NotEqual v2) /\
   Eval s env (BOOL (b1 \/ b2)) (BBOp v1 Or v2)`,
 rw [Eval_def, erun_def, BOOL_def, sum_bind_def, erun_bbop_def]);

val Eval_BOOL_And = Q.store_thm("Eval_BOOL_And",
 `!s b1 v1 b2 v2.
   Eval s env (BOOL b1) v1 /\
   Eval s env (BOOL b2) v2 ==>
   Eval s env (BOOL (b1 /\ b2)) (BBOp v1 And v2)`,
 rw [Eval_BOOL_bbop]);

val Eval_BOOL_Equal = Q.store_thm("Eval_BOOL_Equal",
 `!s b1 v1 b2 v2.
   Eval s env (BOOL b1) v1 /\
   Eval s env (BOOL b2) v2 ==>
   Eval s env (BOOL (b1 = b2)) (BBOp v1 Equal v2)`,
 rw [Eval_BOOL_bbop]);

val Eval_BOOL_NotEqual = Q.store_thm("Eval_BOOL_NotEqual",
 `!s b1 v1 b2 v2.
   Eval s env (BOOL b1) v1 /\
   Eval s env (BOOL b2) v2 ==>
   Eval s env (BOOL (b1 <> b2)) (BBOp v1 NotEqual v2)`,
 rw [Eval_BOOL_bbop]);

val Eval_BOOL_Or = Q.store_thm("Eval_BOOL_Or",
 `!s b1 v1 b2 v2.
   Eval s env (BOOL b1) v1 /\
   Eval s env (BOOL b2) v2 ==>
   Eval s env (BOOL (b1 \/ b2)) (BBOp v1 Or v2)`,
 rw [Eval_BOOL_bbop]);

val band_w2v = Q.store_thm("band_w2v",
 `!w1 w2. band (w2v w1) (w2v w2) = w2v (w1 && w2)`,
 rpt gen_tac \\ bitstringLib.Cases_on_v2w `w1` \\  bitstringLib.Cases_on_v2w `w2` \\
 fs [w2v_v2w, w2v_v2w, bitwise_def, (* spec: *) word_and_v2w, band_def]);

val bor_w2v = Q.store_thm("bor_w2v",
 `!w1 w2. bor (w2v w1) (w2v w2) = w2v (w1 || w2)`,
 rpt gen_tac \\ bitstringLib.Cases_on_v2w `w1` \\  bitstringLib.Cases_on_v2w `w2` \\
 fs [w2v_v2w, w2v_v2w, bitwise_def, (* spec: *) word_or_v2w, bor_def]);

val bxor_w2v = Q.store_thm("bxor_w2v",
 `!w1 w2. bxor (w2v w1) (w2v w2) = w2v (w1 ⊕ w2)`,
 rpt gen_tac \\ bitstringLib.Cases_on_v2w `w1` \\  bitstringLib.Cases_on_v2w `w2` \\
 fs [w2v_v2w, w2v_v2w, bitwise_def, (* spec: *) word_xor_v2w, bxor_def]);

val Eval_WORD_abop = Q.store_thm("Eval_WORD_abop",
 `!s w1 v1 w2 v2.
   Eval s env (WORD w1) v1 /\
   Eval s env (WORD w2) v2 ==>
   Eval s env (WORD (w1 && w2)) (ABOp v1 BitwiseAnd v2) /\
   Eval s env (WORD (w1 || w2)) (ABOp v1 BitwiseOr v2) /\
   Eval s env (WORD (w1 ⊕ w2)) (ABOp v1 BitwiseXor v2)`,
 rw [Eval_def, erun_def, WORD_def] \\ res_tac \\
 fs [sum_bind_def, sum_for_def, sum_map_def,
     ver2v_w2ver, v2ver_def, w2ver_def,
     erun_abop_def, same_shape_w2ver, band_w2v, bor_w2v, bxor_w2v]);

val Eval_WORD_And = Q.store_thm("Eval_WORD_And",
 `!s w1 v1 w2 v2.
   Eval s env (WORD w1) v1 /\
   Eval s env (WORD w2) v2 ==>
   Eval s env (WORD (w1 && w2)) (ABOp v1 BitwiseAnd v2)`,
 rw [Eval_WORD_abop]);

val Eval_WORD_Or = Q.store_thm("Eval_WORD_Or",
 `!s w1 v1 w2 v2.
   Eval s env (WORD w1) v1 /\
   Eval s env (WORD w2) v2 ==>
   Eval s env (WORD (w1 || w2)) (ABOp v1 BitwiseOr v2)`,
 rw [Eval_WORD_abop]);

val Eval_WORD_Xor = Q.store_thm("Eval_WORD_Xor",
  `!s w1 v1 w2 v2.
    Eval s env (WORD w1) v1 /\
    Eval s env (WORD w2) v2 ==>
    Eval s env (WORD (w1 ⊕ w2)) (ABOp v1 BitwiseXor v2)`,
 rw [Eval_WORD_abop]);

(* These thms are ugly as we are working on list of values, rather than arrays *)
val erun_shift_ShiftArithR_word_ast_bv = Q.store_thm("erun_shift_ShiftArithR_word_ast_bv",
 `!w1 w2. erun_shift ShiftArithR (MAP VBool (w2v w1)) (w2n w2) = MAP VBool (w2v (w1 >>~ w2))`,
 cheat);

val Eval_WORD_shift = Q.store_thm("Eval_WORD_shift",
  `!s w1 v1 w2 v2.
    Eval s env (WORD w1) v1 /\
    Eval s env (WORD w2) v2 ==>
    Eval s env (WORD (w1 >>~ w2)) (Shift v1 ShiftArithR v2) /\
    Eval s env (WORD (w1 <<~ w2)) (Shift v1 ShiftLogicalL v2) /\
    Eval s env (WORD (w1 >>>~ w2)) (Shift v1 ShiftLogicalR v2)`,
 cheat);
(*
 rw [Eval_def, erun_def] \\ res_tac \\
 fs [sum_bind_def, sum_for_def, sum_map_def,
     WORD_def, get_1dim_VArray_data_def, erun_shift_def,
     w2ver_def, ver2v_def, ver2n_def, v2n_w2v, sum_mapM_ver2bool_VBool,
     w2v_not_empty, EVERY_isVBool_MAP_VBool,
     erun_shift_ShiftArithR_word_ast_bv]);
*)

val Eval_WORD_ShiftArithR = Q.store_thm("Eval_WORD_ShiftArithR",
  `!s w1 v1 w2 v2.
    Eval s env (WORD w1) v1 /\
    Eval s env (WORD w2) v2 ==>
    Eval s env (WORD (w1 >>~ w2)) (Shift v1 ShiftArithR v2)`,
 rw [Eval_WORD_shift]);

val Eval_WORD_ShiftLogicalL = Q.store_thm("Eval_WORD_ShiftLogicalL",
  `!s w1 v1 w2 v2.
    Eval s env (WORD w1) v1 /\
    Eval s env (WORD w2) v2 ==>
    Eval s env (WORD (w1 <<~ w2)) (Shift v1 ShiftLogicalL v2)`,
 rw [Eval_WORD_shift]);

val Eval_WORD_ShiftLogicalR = Q.store_thm("Eval_WORD_ShiftLogicalR",
  `!s w1 v1 w2 v2.
    Eval s env (WORD w1) v1 /\
    Eval s env (WORD w2) v2 ==>
    Eval s env (WORD (w1 >>>~ w2)) (Shift v1 ShiftLogicalR v2)`,
 rw [Eval_WORD_shift]);

val Eval_WORD_arith = Q.store_thm("Eval_WORD_arith",
 `!s w1 v1 w2 v2.
   Eval s env (WORD w1) v1 /\
   Eval s env (WORD w2) v2 ==>
   Eval s env (WORD (w1 - w2)) (Arith v1 Minus v2) /\
   Eval s env (WORD (w1 + w2)) (Arith v1 Plus v2) /\
   Eval s env (WORD (w1 * w2)) (Arith v1 Times v2)`,
 rw [Eval_def, erun_def, WORD_def] \\ res_tac \\ PURE_REWRITE_TAC [GSYM WORD_NEG_MUL] \\
 rw [sum_bind_def, sum_map_def,
     w2ver_def, ver2n_def, n2ver_def, v2ver_def, ver2v_def, v2n_w2v,
     same_shape_w2ver, ver_mapVArray_def, sum_mapM_VBool, ver_liftVArray_def, erun_arith_def,

     (* new thms: *) w2v_n2w, ver_fixwidth_fixwidth_MAP,

     (* specific for add *) word_add_def, word_mul_def, word_2comp_def, dimword_def]);

val Eval_WORD_Minus = Q.store_thm("Eval_WORD_Minus",
 `!s w1 v1 w2 v2.
   Eval s env (WORD w1) v1 /\
   Eval s env (WORD w2) v2 ==>
   Eval s env (WORD (w1 - w2)) (Arith v1 Minus v2)`,
 rw [Eval_WORD_arith]);

val Eval_WORD_Plus = Q.store_thm("Eval_WORD_Plus",
 `!s w1 v1 w2 v2.
   Eval s env (WORD w1) v1 /\
   Eval s env (WORD w2) v2 ==>
   Eval s env (WORD (w1 + w2)) (Arith v1 Plus v2)`,
 rw [Eval_WORD_arith]);

val Eval_WORD_Times = Q.store_thm("Eval_WORD_Times",
 `!s w1 v1 w2 v2.
   Eval s env (WORD w1) v1 /\
   Eval s env (WORD w2) v2 ==>
   Eval s env (WORD (w1 * w2)) (Arith v1 Times v2)`,
 rw [Eval_WORD_arith]);

(* UGLY: Everything with this proof is ugly *)
val ver_msb_w2ver = Q.store_thm("ver_msb_w2ver",
 `!w. ver_msb (w2ver w) = INR (word_msb w)`,
 rw [w2ver_def] \\ bitstringLib.Cases_on_v2w `w` \\
 fs [w2v_v2w, word_msb_v2w, markerTheory.Abbrev_def] \\
 Cases_on `v` \\ fs [testbit_el, ver_msb_def]);

val Eval_WORD_cmp = Q.store_thm("Eval_WORD_cmp",
 `!s w1 v1 w2 v2.
   Eval s env (WORD w1) v1 /\
   Eval s env (WORD w2) v2 ==>
   Eval s env (BOOL (w1 = w2)) (Cmp v1 ArrayEqual v2) /\
   Eval s env (BOOL (w1 <> w2)) (Cmp v1 ArrayNotEqual v2) /\
   Eval s env (BOOL (w1 < w2)) (Cmp v1 LessThan v2) /\
   Eval s env (BOOL (w1 <+ w2)) (Cmp v1 LowerThan v2)`,
 rw [Eval_def, erun_def, erun_cmp_def,
     WORD_def, BOOL_def, same_shape_w2ver, w2ver_bij, ver2n_w2ver,
     sum_bind_def, sum_for_def, sum_map_def]
 >- simp [ver_msb_w2ver, WORD_LT, sum_bind_def, sum_map_def]
 \\ (Cases_on_word `w1` \\ Cases_on_word `w2` \\ simp [w2n_n2w, word_lo_n2w]));

val Eval_WORD_Equal = Q.store_thm("Eval_WORD_Equal",
 `!s w1 v1 w2 v2.
   Eval s env (WORD w1) v1 /\
   Eval s env (WORD w2) v2 ==>
   Eval s env (BOOL (w1 = w2)) (Cmp v1 ArrayEqual v2)`,
 rw [Eval_WORD_cmp]);

val Eval_WORD_NotEqual = Q.store_thm("Eval_WORD_NotEqual",
 `!s w1 v1 w2 v2.
   Eval s env (WORD w1) v1 /\
   Eval s env (WORD w2) v2 ==>
   Eval s env (BOOL (w1 <> w2)) (Cmp v1 ArrayNotEqual v2)`,
 rw [Eval_WORD_cmp]);

val Eval_WORD_LessThan = Q.store_thm("Eval_WORD_LessThan",
 `!s w1 v1 w2 v2.
   Eval s env (WORD w1) v1 /\
   Eval s env (WORD w2) v2 ==>
   Eval s env (BOOL (w1 < w2)) (Cmp v1 LessThan v2)`,
 rw [Eval_WORD_cmp]);

val Eval_WORD_LowerThan = Q.store_thm("Eval_WORD_LowerThan",
 `!s w1 v1 w2 v2.
   Eval s env (WORD w1) v1 /\
   Eval s env (WORD w2) v2 ==>
   Eval s env (BOOL (w1 <+ w2)) (Cmp v1 LowerThan v2)`,
 rw [Eval_WORD_cmp]);

val Eval_word_bit = Q.store_thm("Eval_word_bit",
 `!s n (w:'a word) var.
    n < dimindex (:'a) /\
    Eval s env (WORD w) (Var var) ==>
    Eval s env (BOOL (word_bit n w)) (ArrayIndex var [Const (n2ver n)])`,
 rw [Eval_def, erun_def, WORD_def] \\ res_tac \\
 rw [sum_bind_def, sum_mapM_def, erun_def, sum_map_def, ver2n_n2ver, w2ver_def,
     get_array_index_def, sum_revEL_def] \\
 bitstringLib.Cases_on_v2w `w` \\
 fs [w2v_v2w, BOOL_def, sum_bind_def, EL_MAP, bit_v2w, testbit, sum_EL_EL]);

val Eval_word_extract_help = Q.store_thm("Eval_word_extract_help",
 `!v h l. h >= l /\ h < LENGTH v ==> TAKE (h − l + 1) (DROP (LENGTH v − (h + 1)) v) = DROP (LENGTH v − SUC h) (TAKE (LENGTH v − l) v)`,
 Induct \\ rw [] \\ Cases_on `LENGTH v = h'` \\ fs [arithmeticTheory.ADD1, DROP_def, TAKE_def]);

val Eval_word_extract = Q.store_thm("Eval_word_extract",
 `!s (w:'a word) var h l.
   Eval s env (WORD w) (Var var) ==>
   h >= l /\ h < dimindex (:'a) /\ h - l + 1 = dimindex (:'b) /\ dimindex (:'a) >= dimindex (:'b) ==>
   Eval s env (WORD (((h >< l) w):'b word)) (ArraySlice var [] h l)`,
 rw [Eval_def, erun_def, WORD_def, sum_bind_def] \\
 ntac 2 (pop_assum (fn _ => all_tac)) (* <-- just cleanup *) \\

 rw [w2ver_def, get_array_slice_def] \\ rewrite_tac [GSYM MAP_DROP, GSYM MAP_TAKE] \\ irule MAP_CONG >- rw [] \\
 bitstringLib.Cases_on_v2w `w` \\ fs [word_extract_v2w, word_bits_v2w, w2v_v2w, w2w_v2w, field_def, shiftr_def] \\
 fs [fixwidth_def, zero_extend_def, PAD_LEFT] \\ metis_tac [Eval_word_extract_help]);

val MAP_PAD_LEFT = Q.store_thm("MAP_PAD_LEFT",
 `!f x n l. MAP f (PAD_LEFT x n l) = PAD_LEFT (f x) n (MAP f l)`,
 rw [PAD_LEFT, MAP_GENLIST]);

val Eval_resize_tac =
 rw [BOOL_def, WORD_def, Eval_def, erun_def, erun_resize_def] \\
 first_x_assum drule \\ strip_tac \\
 rw [sum_bind_def, sum_map_def, get_1dim_VArray_data_def, ver_to_VArray_def, isVBool_def,
       w2ver_def, EVERY_isVBool_MAP_VBool,
       w2v_not_empty, w2v_w2w, w2v_v2w,
       fixwidth_def, zero_extend_def, MAP_PAD_LEFT, MAP_DROP];

val Eval_w2w = Q.store_thm("Eval_w2w",
 `!s (w:'a word) e.
   Eval s env (WORD w) e ==>
   Eval s env (WORD ((w2w w):'b word)) (Resize e ZeroExtend (dimindex (:'b)))`,
 Eval_resize_tac);

val HD_MAP = Q.store_thm("HD_MAP",
 `!l f. l <> [] ==> HD (MAP f l) = f (HD l)`,
 Cases \\ rw []);

val GENLIST_NIL = Q.store_thm("GENLIST_NIL",
 `!f n. GENLIST f n = [] <=> n = 0`,
 Cases_on `n` \\ simp [GENLIST]);

val PAD_LEFT_MAP = Q.store_thm("PAD_LEFT_MAP",
 `!l f x n. PAD_LEFT (f x) n (MAP f l) = MAP f (PAD_LEFT x n l)`,
 rw [PAD_LEFT, MAP_GENLIST]);

val HD_GENLIST_alt = Q.store_thm("HD_GENLIST_alt",
 `!n f. 0 < n ==> HD (GENLIST f n) = f 0`,
 Cases \\ rw [HD_GENLIST]);

val GENLIST_APPEND_alt = Q.store_thm("GENLIST_APPEND_alt",
 `!m n f g.
   m < n ==> GENLIST f (n - m) ++ GENLIST g m =
             GENLIST (\i. if i < (n - m) then f i else g (i - (n - m))) n`,
 rpt strip_tac \\ `n = m + (n - m)` by DECIDE_TAC \\
 pop_assum (fn th => CONV_TAC (RHS_CONV (ONCE_REWRITE_CONV [th]))) \\
 rewrite_tac [GENLIST_APPEND] \\ match_mp_tac f_equals2 \\ rw [GENLIST_CONG]);

val Eval_sw2sw = Q.store_thm("Eval_sw2sw",
 `!s (w:'a word) e.
   dimindex(:'a) < dimindex (:'b) /\
   Eval s env (WORD w) e ==>
   Eval s env (WORD ((sw2sw w):'b word)) (Resize e SignExtend (dimindex (:'b)))`,
 (* TODO: Generalize tactic *)
 Eval_resize_tac \\
 simp [w2v_def, sw2sw] \\
 DEP_REWRITE_TAC [HD_MAP] \\ conj_tac >- rw [GENLIST_NIL] \\
 simp [PAD_LEFT_MAP] \\ match_mp_tac MAP_CONG \\ simp [PAD_LEFT] \\
 DEP_REWRITE_TAC [HD_GENLIST_alt] \\ simp [] \\
 `!i. 0 < i + dimindex (:'a)` by (gen_tac \\ assume_tac DIMINDEX_GT_0 \\ DECIDE_TAC) \\ simp [] \\
 pop_assum (fn _ => ALL_TAC) \\
 simp [GENLIST_APPEND_alt, word_msb_def] \\ match_mp_tac GENLIST_CONG \\ rw [f_equals2]);

val Eval_v2w = Q.store_thm("Eval_v2w",
 `!s b e.
   1 < dimindex (:'b) /\
   Eval s env (BOOL b) e ==>
   Eval s env (WORD ((v2w [b]):'b word)) (Resize e ZeroExtend (dimindex (:'b)))`,
 Eval_resize_tac);

val Eval_InlineIf = Q.store_thm("Eval_InlineIf",
 `!s a c cexp l lexp r rexp.
   Eval s env (BOOL c) cexp /\
   Eval s env (a l) lexp /\
   Eval s env (a r) rexp ==>
   Eval s env (a (if c then l else r)) (InlineIf cexp lexp rexp)`,
 rw [BOOL_def, Eval_def, erun_def, sum_bind_def, get_VBool_data_def]);

val Eval_WORD_ARRAY_indexing = Q.store_thm("Eval_WORD_ARRAY_indexing",
 `!s wa var i iexp.
   Eval s env (WORD_ARRAY wa) (Var var) /\
   Eval s env (WORD i) iexp ==>
   Eval s env (WORD (wa i)) (ArrayIndex var [iexp])`,
 rw [WORD_def, WORD_ARRAY_def, Eval_def, erun_def] \\ res_tac \\
 simp [sum_bind_def, sum_mapM_def, sum_map_def, ver2n_w2ver] \\
 Cases_on `res` \\ fs [get_array_index_def, sum_bind_def]);

val Eval_neg = Q.store_thm("Eval_neg",
 `!s b bexp.
   Eval s env (BOOL b) bexp ==>
   Eval s env (BOOL ~b) (BUOp Not bexp)`,
 rw [BOOL_def, Eval_def, erun_def, sum_bind_def, ver_liftVBool_def]);

(** Some assignment thms **)

val set_index_LENGTH = Q.store_thm("set_index_LENGTH",
 `!l l' i v. set_index i l v = INR l' ==> LENGTH l' = LENGTH l`,
 Induct \\ rw [set_index_def] \\ Cases_on `l'` \\ Cases_on `i` \\
 fs [set_index_def, sum_for_def] \\
 imp_res_tac sum_map_INR \\ fs [sum_map_def] \\
 rveq \\ first_x_assum match_mp_tac \\ asm_exists_tac \\ fs []);

val set_index_correct_help = Q.store_thm("set_index_correct_help",
 `!i l v.
   i < LENGTH l /\ EVERY (\e. same_shape v e) l ==>
   ?l'. set_index i l v = INR l' /\
        !i'. sum_EL i' l' = if i' = i then INR v else sum_EL i' l`,
 Induct \\ rpt strip_tac \\ Cases_on `l` \\ fs [set_index_def]
 >- (Cases \\ rw [sum_EL_def])
 \\ first_x_assum drule \\ disch_then drule \\ strip_tac \\ fs [sum_for_def, sum_map_def] \\
    gen_tac \\ Cases_on `i' = SUC i` \\ fs [sum_EL_def] \\ imp_res_tac set_index_LENGTH \\
    Cases_on `i'` \\ fs [sum_EL_def]);

val set_index_correct = Q.store_thm("set_index_correct",
 `!i l v.
   i < LENGTH l /\ EVERY (\e. same_shape v e) l ==>
   ?l'. set_index (LENGTH l − i - 1) l v = INR l' /\
        !i'. sum_revEL i' l' = (if i' = i then INR v else sum_revEL i' l) /\
        LENGTH l' = LENGTH l`,
 rw [sum_revEL_def] \\
 `LENGTH l − (i + 1) < LENGTH l` by DECIDE_TAC \\
 drule set_index_correct_help \\ disch_then drule \\ strip_tac \\
 asm_exists_tac \\ fs [] \\ gen_tac \\ imp_res_tac set_index_LENGTH \\
 Cases_on `i' = i` \\ fs []);

(* Similar to EVERY_EL, just one direction for now *)
val EVERY_sum_revEL = Q.store_thm("EVERY_sum_revEL",
 `!l P. (!n. n < LENGTH l ==> ?e. sum_revEL n l = INR e /\ P e) ==> EVERY P l`,
 Induct >- rw [sum_revEL_def] \\ rw []
 >- (first_x_assum (qspec_then `LENGTH l` assume_tac) \\ fs [sum_revEL_LENGTH])
 \\ first_x_assum match_mp_tac \\ rpt strip_tac \\
    `n < SUC (LENGTH l)` by DECIDE_TAC \\ res_tac \\
    metis_tac [sum_revEL_APPEND_EQN, rich_listTheory.CONS_APPEND]);

(* WORD_ARRAY unfolded once here *)
val WORD_ARRAY_EVERY_same_shape = Q.store_thm("WORD_ARRAY_EVERY_same_shape",
 `!l (lw:'a word -> 'b word) (vw:'b word).
   LENGTH l <= dimword (:'a) /\ (!i. sum_revEL (w2n i) l = INR (w2ver (lw i))) ==>
   EVERY (λe. same_shape (w2ver vw) e) l`,
 rpt strip_tac \\ match_mp_tac EVERY_sum_revEL \\ rpt strip_tac \\
 first_x_assum (qspec_then `n2w n` assume_tac) \\
 `n < dimword (:'a)` by DECIDE_TAC \\
 fs [w2n_n2w, LESS_MOD, same_shape_w2ver]);

val prun_bassn_correct = Q.store_thm("prun_bassn_correct",
 `!iw ie iv vw v l lw var i s.
   WORD_ARRAY (lw:'a word -> 'b word) (VArray l) /\
   erun s ie = INR iv /\ WORD (iw:'a word) iv /\ ver2n iv = INR i /\
   WORD (vw:'b word) v /\
   get_var s var = INR (VArray l)
   ==>
   ?s'. prun_bassn s (ArrayIndex var [ie]) v = INR (NONE:value option, s') /\
        ?l'.
         (!var'. get_var s' var' = (if var' = var then INR (VArray l') else get_var s var')) /\
         !i'. sum_revEL i' l' = (if i' = i then INR v else sum_revEL i' l) /\
         LENGTH l' = LENGTH l`,
 rw [prun_bassn_def, assn_def] \\ fs [sum_bind_def, get_VArray_data_def, prun_set_var_index_def] \\
 fs [WORD_ARRAY_def, WORD_def] \\ rveq \\ fs [ver2n_w2ver] \\ rveq \\ IF_CASES_TAC
 >- fs [GSYM NOT_LESS, w2n_lt] \\ `w2n iw < LENGTH l` by DECIDE_TAC \\
 drule set_index_correct \\ disch_then (qspec_then `w2ver vw` mp_tac) \\ impl_tac
 >- (match_mp_tac WORD_ARRAY_EVERY_same_shape \\ fs [] \\ metis_tac [])
 \\ strip_tac \\ rfs [sum_for_def, sum_map_def] \\
    qexists_tac `l'` \\ rw [get_var_set_var]);

(** EvalS thms **)

val EvalS_If = Q.store_thm("EvalS_If",
 `!s C Cexp L Lvprog R Rvprog.
   Eval s env (BOOL C) Cexp /\
   EvalS s env L Lvprog /\
   EvalS s env R Rvprog ==>
   EvalS s env (if C then L else R) (IfElse Cexp Lvprog Rvprog)`,
 rewrite_tac [EvalS_def, Eval_def, prun_def] \\ rpt STRIP_TAC \\ res_tac \\
 fs [sum_bind_def, BOOL_def, get_VBool_data_def] \\
 TOP_CASE_TAC \\ fs []);

(* Thms for let translation *)

val EvalS_Let = Q.store_thm("EvalS_Let",
 `!s name a arg arg_exp f f_exp.
  ~state_var name /\
  prun_bassn_type_pred a /\
  Eval s env (a arg) arg_exp /\
  (!v. a arg v ==> EvalS s ((name, v) :: env) (f arg) f_exp) ==>
  var_has_type env name a ==>
  EvalS s env (LET f arg) (Seq (BlockingAssign (Var name) arg_exp) f_exp)`,
 rw [EvalS_def, Eval_def, prun_Seq] \\ rw [prun_def] \\
 first_x_assum drule \\ strip_tac \\ fs [sum_bind_def, prun_bassn_type_pred_def] \\
 res_tac \\ simp [] \\
 first_x_assum (qspec_then `res` mp_tac) \\ impl_tac >- rw [] \\
 rw [relS_not_state_var]);

val var_has_value_env_new_var = Q.store_thm("var_has_value_env_new_var",
 `!var var' v a exp env.
   var_has_value ((var', v)::env) var (a exp) =
   if var' = var then a exp v else var_has_value env var (a exp)`,
 rw [var_has_value_def]);

val var_has_type_env_new_var = Q.store_thm("var_has_type_env_new_var",
 `!var var' v a exp env.
   var_has_type ((var', v)::env) var a =
   if var' = var then (?hrep. a hrep v) else var_has_type env var a`,
 rw [var_has_type_def, var_has_value_def]);

(* State bubbling thm, also for translating lets *)

val bubble_var_has_value = Q.store_thm("bubble_var_has_value",
 `!name p ver_s ver_s' v a y P.
   ((prun (ver_s with vars := env) p = INR (v, ver_s')) ==>
    var_has_value ver_s'.vars name (a y) ==>
    P) ==>
   ~MEM name (vwrites p)
   ==>
   (var_has_value env name (a y) ==>
    (prun (ver_s with vars := env) p = INR (v, ver_s')) ==>
    P)`,
 rw [AND_IMP_INTRO] \\ first_x_assum match_mp_tac \\ imp_res_tac prun_same_after \\
 fs [get_var_def, var_has_value_def] \\ every_case_tac \\ fs []);

val bubble_var_has_type = Q.store_thm("bubble_var_has_type",
 `!name p ver_s ver_s' v a y P.
   ((prun (ver_s with vars := env) p = INR (v, ver_s')) ==>
    var_has_type ver_s'.vars name a ==>
    P) ==>
   ~MEM name (vwrites p)
   ==>
   (var_has_type env name a ==>
    (prun (ver_s with vars := env) p = INR (v, ver_s')) ==>
    P)`,
 rw [AND_IMP_INTRO] \\ first_x_assum match_mp_tac \\ imp_res_tac prun_same_after \\
 fs [get_var_def, var_has_type_def, var_has_value_def] \\ every_case_tac \\ fs [] \\
 rveq \\ asm_exists_tac \\ simp []);

val EvalS_EvalS = Q.store_thm("EvalS_EvalS",
 `!s env f fv g gv.
   EvalS s env f fv /\
   (!s' vs vs' fvv. prun (vs with vars := env) fv = INR (fvv, vs') ==>
                    EvalS s' vs'.vars ((\s. g s) s') gv) ==>
   EvalS s env (LET g f) (Seq fv gv)`,
 rw [EvalS_def, prun_Seq] \\ first_x_assum drule \\ strip_tac \\ simp [] \\
 (* UGLY: mp_tac then impl_tac *)
 first_x_assum drule \\ disch_then (qspecl_then [`f`, `ver_s'`] mp_tac) \\
 fs [pstate_vars_cleanup]);

(* Thms for case translation *)

(* Note: Works for any program q rather than just ARB, but we only ever need ARB *)
val EvalS_Case_ARB = Q.store_thm("EvalS_Case_ARB",
 `!s x_max (x:'a word) xv p pv.
   x_max = UINT_MAXw /\
   Eval s env (WORD x) xv /\
   EvalS s env p pv ==>
   x_max <=+ x  ==>
   EvalS s env (if x = x_max then p else ARB) (Case xv [(Const (w2ver x_max), pv)] NONE)`,
 rpt strip_tac \\ rveq \\ TOP_CASE_TAC
 >- (fs [EvalS_def, Eval_def, prun_def, erun_def, WORD_def] \\ rpt strip_tac \\ res_tac \\
     simp [sum_bind_def])
 \\ (qspec_then `x` assume_tac WORD_LS_T \\ fs [WORD_LS] \\
    `w2n x = w2n (-1w:'a word)` by DECIDE_TAC \\ fs []));

val word_lo_word_ls_plus1 = Q.store_thm("word_lo_word_ls_plus1",
 `!x y. x <+ y ==> x + 1w <=+ y`,
 rpt strip_tac \\ qspec_then `x` mp_tac w2n_plus1 \\ TOP_CASE_TAC \\ WORD_DECIDE_TAC);

val word_ls_0 = Q.store_thm("word_ls_0",
 `!x. 0w <=+ x`, WORD_DECIDE_TAC);

(* Accumulate thm for _Case_ARB *)
val EvalS_Case_ARB_new_case = Q.store_thm("EvalS_Case_ARB_new_case",
 `!s xbound_new xbound (x:'a word) xv p pv q cs defl.
   (xbound = xbound_new + 1w) /\
   Eval s env (WORD x) xv /\
   (xbound <=+ x ==> EvalS s env q (Case xv cs defl)) /\
   EvalS s env p pv ==>

   (xbound_new <=+ x ==>
   EvalS s env (if x = xbound_new then p else q)
               (Case xv ((Const (w2ver xbound_new), pv)::cs) defl))`,
 rw [EvalS_def, Eval_def, WORD_def, prun_def, erun_def] \\ res_tac \\
 simp [sum_bind_def, w2ver_bij] \\
 `xbound_new <+ x` by WORD_DECIDE_TAC \\
 fs [word_lo_word_ls_plus1]);

val EvalS_Case_catch_all = Q.store_thm("EvalS_Case_catch_all",
 `!s xval x xv p pv.
   Eval s env (WORD x) xv /\
   EvalS s env p pv ==>
   EvalS s env p (Case xv [] (SOME pv))`,
 rw [EvalS_def, prun_def]);

val EvalS_Case_catch_all_new_case = Q.store_thm("EvalS_Case_catch_all_new_case",
 `!s xval x xv p pv q qv cs.
   Eval s env (WORD x) xv /\
   EvalS s env q (Case xv cs (SOME qv)) /\
   EvalS s env p pv ==>
   EvalS s env (if x = xval then p else q)
               (Case xv ((Const (w2ver xval), pv)::cs) (SOME qv))`,
 rpt strip_tac \\ fs [EvalS_def, Eval_def, erun_def, prun_def] \\ rpt strip_tac \\
 last_x_assum (qspec_then `ver_s` assume_tac) \\ fs [sum_bind_def, WORD_def] \\
 rw [w2ver_bij]);

(* Microoptimization *)
val EvalS_Case_catch_all' = Q.store_thm("EvalS_Case_catch_all'",
 `!s xval x xv p pv q qv.
   Eval s env (WORD x) xv /\
   EvalS s env p pv /\
   EvalS s env q qv ==>
   EvalS s env (if x = xval then p else q)
               (Case xv [(Const (w2ver xval), pv)] (SOME qv))`,
 metis_tac [EvalS_Case_catch_all, EvalS_Case_catch_all_new_case]);

val EvalS_Skip = Q.store_thm("EvalS_Skip",
 `!s. EvalS s env s Skip`,
 rw [EvalS_def, prun_def]);

val _ = export_theory();
