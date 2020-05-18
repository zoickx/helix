Require Import Coq.Arith.Arith.
Require Import Psatz.

Require Import Coq.Strings.String.

Notation "x @@ y" := (String.append x y) (right associativity, at level 60) : string_scope.

  Lemma string_cons_app :
    forall x y,
      String x y = ((String x "") @@ y)%string.
  Proof.
    reflexivity.
  Qed.

  Lemma string_app_assoc :
    forall (a b c : string),
      eq (a @@ (b @@ c))%string ((a @@ b) @@ c)%string.
  Proof.
    intros a b c.
    induction a.
    - reflexivity.
    - simpl. rewrite IHa.
      reflexivity.
  Qed.

    Ltac rev_str_helper acc s :=
      match s with
      | EmptyString => acc
      | (String ?x ?y) =>
        rev_str_helper (String x acc) y
      end.

    Ltac rev_str s := rev_str_helper EmptyString s.

    Ltac rewrite_str acc s :=
      match s with
      | (String ?x EmptyString) =>
        let r := rev_str acc in
        constr:(r)
      | (String ?x ?y) => rewrite_str (String x acc) y
      end.

    Ltac last_str s :=
      match s with
      | (String ?x EmptyString) => constr:(String x EmptyString)
      | (String ?x ?y) => last_str y
      end.

    Ltac make_append_str s :=
      match s with
      | (String ?x ?y) =>
        let rs := rewrite_str EmptyString (String x y) in
        let ls := last_str y in
        replace (String x y) with (rs @@ ls)%string by reflexivity
      end.

Import Coq.Strings.String Strings.Ascii.
Open Scope string_scope.
Open Scope char_scope.

Require Import Coq.Lists.List.

Require Import Coq.Numbers.BinNums. (* for Z scope *)
Require Import Coq.ZArith.BinInt.

Require Import Helix.FSigmaHCOL.FSigmaHCOL.
Require Import Helix.FSigmaHCOL.Int64asNT.
Require Import Helix.DSigmaHCOL.DSigmaHCOLITree.
Require Import Helix.LLVMGen.Compiler.
Require Import Helix.LLVMGen.Externals.
Require Import Helix.LLVMGen.Data.
Require Import Helix.LLVMGen.Utils.
Require Import Helix.LLVMGen.tmp_aux_Vellvm.
Require Import Helix.Util.OptionSetoid.
Require Import Helix.Util.ErrorSetoid.
Require Import Helix.Util.ListUtil.
Require Import Helix.Tactics.HelixTactics.

Require Import ExtLib.Structures.Monads.
Require Import ExtLib.Data.Map.FMapAList.

Require Import Vellvm.Util.
Require Import Vellvm.LLVMEvents.
Require Import Vellvm.DynamicTypes.
Require Import Vellvm.Denotation.
Require Import Vellvm.Handlers.Handlers.
Require Import Vellvm.TopLevel.
Require Import Vellvm.LLVMAst.
Require Import Vellvm.CFG.
Require Import Vellvm.InterpreterMCFG.
Require Import Vellvm.InterpreterCFG.
Require Import Vellvm.TopLevelRefinements.
Require Import Vellvm.TypToDtyp.
Require Import Vellvm.LLVMEvents.

Require Import Ceres.Ceres.

Require Import ITree.Interp.TranslateFacts.
Require Import ITree.Basics.CategoryFacts.
Require Import ITree.Events.State.
Require Import ITree.Events.StateFacts.
Require Import ITree.ITree.
Require Import ITree.Eq.Eq.
Require Import ITree.Basics.Basics.
Require Import ITree.Interp.InterpFacts.

Require Import Flocq.IEEE754.Binary.
Require Import Flocq.IEEE754.Bits.

Require Import MathClasses.interfaces.canonical_names.
Require Import MathClasses.misc.decision.

Require Import Omega.

Set Implicit Arguments.
Set Strict Implicit.

Import MDSHCOLOnFloat64.
Import D.
(* IO.  *)
Import ListNotations.
Import MonadNotation.
Local Open Scope monad_scope.

(* A couple of notations to avoid ambiguities while not having to worry about imports and qualified names *)
Notation memoryV := memory_stack.
Notation memoryH := MDSHCOLOnFloat64.memory.

Section EventTranslation.

  (* We relate Helix trees and Vellvm trees at a point where their event signatures are still not empty.
   To do so, we therefore relate them at the join of these signature, using [translate] to do so.
   Unfortunately, since [vellvm] works over two different set of signatures depending whether
   function calls are already resolved or not, we also need two joins here.

TODOYZ: Principle the approach and move it to [itrees]

NOTEYZ: An alternative would be to translate everything that remains into failure. That could also be
      part of the library as a generic handler.
   *)

  (* Joined set of residual events for full programs *)
  Definition E_mcfg : Type -> Type := (ExternalCallE +' PickE +' UBE +' DebugE +' FailureE) +' (StaticFailE +' DynamicFailE).
  (* Joined set of residual events for cfgs *)
  Definition E_cfg : Type -> Type := (CallE +' PickE +' UBE +' DebugE +' FailureE) +' (StaticFailE +' DynamicFailE).

  (* We define the translation by injection *)
  Definition translate_E_vellvm_mcfg : itree (ExternalCallE +' PickE +' UBE +' DebugE +' FailureE) ~> itree E_mcfg :=
    translate inl_.

  Definition translate_E_vellvm_cfg : itree (CallE +' PickE +' UBE +' DebugE +' FailureE) ~> itree E_cfg :=
    translate inl_.

  Definition translate_E_helix_mcfg : itree (StaticFailE +' DynamicFailE) ~> itree E_mcfg :=
    translate inr_.

  Definition translate_E_helix_cfg : itree (StaticFailE +' DynamicFailE) ~> itree E_cfg :=
    translate inr_.

  (* We therefore have the following resulting denotation functions. *)
  (* On the Vellvm side, for [mcfg]: *)
  Definition semantics_llvm_mcfg p : itree E_mcfg _ := translate_E_vellvm_mcfg (model_to_L3 DTYPE_Void "main" main_args helix_intrinsics p).
  (* Which get lifted to [toplevel_entity] as usual: *)
  Definition semantics_llvm (prog: list (toplevel_entity typ (LLVMAst.block typ * list (LLVMAst.block typ)))) :=
    semantics_llvm_mcfg (mcfg_of_tle prog).

  (* On the Helix side: *)
  (* We first define what amount to initializing the runtime before starting executing the operator *)
  (* NOTEYZ: This should be moved somewhere else, it is part of the semantics of the language, not the compiler's problem *)
  (* NOTEYZ: It's janky that it's happening at the semantics level. Not unheard of, but janky *)
  (* Initialization of globals *)
  Fixpoint denote_initFSHGlobals
           (data: list binary64)
           (globals: list (string * DSHType))
    : itree Event (list binary64 * evalContext) :=
    match globals with
    | [] => ret (data, [])
    | (_,gt)::gs =>
      match gt with
      | DSHnat => Sfail "Unsupported global type: nat"
      | DSHCType =>
        '(data,σ) <- denote_initFSHGlobals data gs ;;
        let '(x, data) := rotate Float64Zero data in
         ret (data, (DSHCTypeVal x)::σ)
      | DSHPtr n =>
        '(data,σ) <- denote_initFSHGlobals data gs ;;
        let (data,mb) := constMemBlock (MInt64asNT.to_nat n) data in
        k <- trigger (MemAlloc n);;
        trigger (MemSet k mb);;
        let p := DSHPtrVal k n in
        ret (data, (p::σ))
      end
    end.

  (** Top-level denotation of an FSHCOL program:
   * initialization of globals
   * allocation of dedicated memory addresses to host the input and output of the program
   * denotation of the operator itself
   *)
  Definition denote_FSHCOL (p:FSHCOLProgram) (data:list binary64)
    : itree Event (list binary64) :=
    '(data, σ) <- denote_initFSHGlobals data p.(globals) ;;
    xindex <- trigger (MemAlloc p.(i));;
    yindex <- trigger (MemAlloc p.(o));;
    let '(data, x) := constMemBlock (MInt64asNT.to_nat p.(i)) data in
    trigger (MemSet xindex x);;

    let σ := List.app σ [DSHPtrVal yindex p.(o); DSHPtrVal xindex p.(i)] in
    denoteDSHOperator σ p.(op);;
    bk <- trigger (MemLU "denote_FSHCOL" yindex);;
    lift_Derr (mem_to_list "Invalid output memory block" (MInt64asNT.to_nat p.(o)) bk).

  (* Finally, the semantics of FSHCOL for the top-level equivalence *)
  Definition semantics_FSHCOL (p: FSHCOLProgram) data : itree E_mcfg (memoryH * list binary64) :=
    translate_E_helix_mcfg (interp_Mem (denote_FSHCOL p data) memory_empty).

End EventTranslation.

(* Facilities to refer to the return types of the various pieces of denotations we manipulate *)

Section StateTypes.

  Local Open Scope type_scope.

  (* Return state of a denoted and interpreted [cfg].
     Note the lack of local stack *)
  Definition LLVM_memory_state_cfg
    := memoryV * (local_env * (global_env)).

  (* Constructor to avoid having to worry about the nesting *)
  Definition mk_LLVM_memory_state_cfg m l g: LLVM_memory_state_cfg := (m,(l,g)).

  (* Return state of a denoted and interpreted [mcfg] *)
  Definition LLVM_memory_state_mcfg
    := memoryV *
       (local_env * @Stack.stack (local_env) * (global_env)).

  (* Return state and value of a denoted and interpreted (open) [cfg].
     Note the lack of local stack.
     Note that we may return a [block_id] alternatively to a [uvalue]
   *)
  Definition LLVM_state_cfg_T (T:Type): Type
    := memoryV * (local_env * (global_env * T)).
  Definition LLVM_state_cfg
    := LLVM_state_cfg_T (block_id + uvalue).

  (* Return state and value of a denoted and interpreted [mcfg]. *)
  Definition LLVM_state_mcfg_T (T:Type): Type
    := memoryV * (local_env * @Stack.stack (local_env) * (global_env * T)).
  Definition LLVM_state_mcfg :=
    LLVM_state_mcfg_T uvalue.

  (* -- Injections -- *)
  (* The nested state transformers associate the products the other way,
     we therefore define injections of memory states and values into return
     types of computations.
   *)
  Definition mk_LLVM_state_cfg_from_mem (T:Type) (v:T): LLVM_memory_state_cfg -> (LLVM_state_cfg_T T)
    := λ '(m, (ρ, g)), (m, (ρ, (g, v))).

  Definition mk_LLVM_state_mcfg_from_mem (T:Type) (v:T): LLVM_memory_state_mcfg -> (LLVM_state_mcfg_T T)
    := λ '(m, (ρ, g)), (m, (ρ, (g, v))).

End StateTypes.

(* Facilities to refer to the type of relations used during the simulations of various pieces of denotions we manipulate *)
(* TODOYZ: Think about those, rename. *)
Section RelationTypes.

  (** Relation of memory states which must be held for
      intialization steps *)
  Definition Type_R_memory_cfg: Type
    := evalContext ->
       memoryH → LLVM_memory_state_cfg → Prop.

  (** Relation of memory states which must be held for
      intialization steps *)
  Definition Type_R_memory_mcfg: Type
    := evalContext ->
       memoryH → LLVM_memory_state_mcfg → Prop.

  (** Type of bisimulation relations between DSHCOL and VIR internal to CFG states,
      parameterized by the types of the computed values.
   *)
  Definition Type_R_cfg_T (TH TV: Type): Type
    := evalContext ->
       memoryH * TH → LLVM_state_cfg_T TV → Prop.

  (* Lifting a relation on memory states to one encompassing returned values by ignoring them *)
  Definition lift_R_memory_cfg (R: Type_R_memory_cfg) (TH TV: Type): Type_R_cfg_T TH TV :=
    fun σ '(memH,_) '(memV,(l,(g,_))) => R σ memH (memV,(l,g)).

  (* Lifting a relation on results to one encompassing states by ignoring them *)
  Definition lift_R_result_cfg {TH TV: Type} (R: TH -> TV -> Prop): Type_R_cfg_T TH TV :=
    fun _ '(_,vh) '(_,(_,(_,vv))) => R vh vv.

  (** Type of bisimulation relations between DSHCOL and VIR internal to CFG states,
      parameterized by the types of the computed values.
   *)
  Definition Type_R_mcfg_T (TH TV: Type): Type
    := evalContext ->
       memoryH * TH → LLVM_state_mcfg_T TV → Prop.

  Definition lift_R_memory_mcfg (R: Type_R_memory_mcfg) (TH TV: Type): Type_R_mcfg_T TH TV :=
    fun σ '(memH,_) '(memV,(l,(g,_))) => R σ memH (memV,(l,g)).

  (** Type of bisimulation relation between DSHCOL and LLVM states.
    This relation could be used for fragments of CFG [cfg].
   *)
  Definition Type_R_partial: Type
    := evalContext ->
       memoryH * () → LLVM_state_cfg → Prop.

  (** Type of bisimulation relation between DSHCOL and LLVM states.
      This relation could be used for "closed" CFG [mcfg].
   *)
  Definition Type_R_full: Type
    := evalContext ->
       memoryH * (list binary64) → LLVM_state_mcfg → Prop.

End RelationTypes.

Section SimulationRelations.

  (**
     We define in this section the principal simulation relations used:
     - At the top-level to relate full [FSHCOLProgram]s to the full Vellvm
     program resulting from their compilation: see [compiler_correct]
     - At the top-level to relate these same program after initialization of
     the runtime. (TODOYZ: Do we need one such?)
     - When relating operators to the sub-cfg resulting from their compilation:
     see [compile_FSHCOL_correct]

    These relations also get refined when related sub-structures of the operators,
    we define these refinements in the corresponding sections.
   *)

  (* TODOYZ: Proof read, comment extensively *)

  (**
     [mem_lookup_llvm_at_i bk_llvm i ptr_size_helix v_llvm] is a judgment asserting that
     an array of [i] doubles can be read from the logical_block [bk_llvm],
     and that this array is precisely [v_llvm].

     NOTEYZ: [handle_gep_h] seems to completely dismiss the size argument in the
     array type. Is the [ptr_size_helix] argument useless?

     TODOYZ: This is weirdly low level. Break it into functions provided by
     Vellvm and rewrite it at a higher level?

   *)
  Definition mem_lookup_llvm_at_i (bk_llvm: logical_block) (i ptr_size_helix: nat) (v_llvm: uvalue): Prop :=
    exists offset,
      match bk_llvm with
      | LBlock _ bk_llvm _ =>
        handle_gep_h (DTYPE_Array (Z.of_nat ptr_size_helix) DTYPE_Double)
                       0
                       [DVALUE_I64 (DynamicValues.Int64.repr (Z.of_nat i))] ≡ inr offset /\
        deserialize_sbytes
          (lookup_all_index offset (sizeof_dtyp DTYPE_Double) bk_llvm SUndef)
          DTYPE_Double ≡ v_llvm
      end.

  (** Injective function from finite naturals [i<domain] to
   arbitrary type.

   NOTEYZ: To see at use, but this dependent record seems overly fancy to me, I'm a bit worried about it.
   If it turns out annoying, a simple function from teh list of element of interest into the image
   and inlining a trivial characterization of the injectivity in the invariant might be simpler.
   *)
  Record injection_Fin (A:Type) (domain : nat) :=
    mk_injection_Fin
      {
        inj_f : nat -> A;
        inj_f_spec :
          forall x y,
            x < domain /\ y < domain ->
            inj_f x ≡ inj_f y ->
            x ≡ y
      }.

  (**
     Relation used to relate memories after the initialization phase.
     Recall: [Type_R_memory ≜ evalContext -> memoryH -> LLVM_memory_state_cfg -> Prop]
     NOTEYZ: Shouldn't it be [(evalContext * memoryH) -> LLVM_memory_state_cfg -> Prop] rather?

     We have [memory_invariant (σ, memh) (meml,l,g)] when:
     - The [evalContext ≜ list DSHVal] can be mapped in an injective way into
       Vellvm. We make sure that injectivity is interpreted over the union of local
       and global environment.
       TODOYZ: Currently assumes a pointer in memory exists for each of these values.
       This is janky, to rethink.
   *)

(* TODOCB: This needs some changes. I think I need to know something about the relationship betwee ι and the vars list in IRState.

   Additionally, how ι is written down is wrong. Not every value in σ
   is a pointer, some values should be pure integer values for
   instance.
 *)

  Definition in_local_or_global {σ_len : nat}
             (ι : injection_Fin raw_id σ_len)
             (ρ : local_env) (g : global_env)
             (x : nat)
             (dv : dvalue) : Prop
    := (* variable is either in local environment *)
      (alist_find _ (inj_f ι x) ρ ≡ Some (dvalue_to_uvalue dv) /\
       alist_find _ (inj_f ι x) g ≡ None) \/
      (* or in global environment *)
      (alist_find _ (inj_f ι x) ρ ≡ None /\
       alist_find _ (inj_f ι x) g ≡ Some dv).

  Definition memory_invariant : Type_R_memory_cfg :=
    fun (σ : evalContext) (mem_helix : MDSHCOLOnFloat64.memory) '(mem_llvm, x) =>
      let σ_len := List.length σ in
      σ_len ≡ 0 \/ (* empty env immediately allowed, as injection could not exists *)
      let '(ρ, g) := x in
      exists (ι: injection_Fin raw_id σ_len),
      forall (x: nat) v,
        nth_error σ x ≡ Some v ->
        match v with
        | DSHnatVal v   =>
          in_local_or_global ι ρ g x
                             (DVALUE_I64 (DynamicValues.Int64.repr (Int64.intval v)))
        | DSHCTypeVal v =>
          in_local_or_global ι ρ g x
                             (DVALUE_Double v)
        | DSHPtrVal ptr_helix ptr_size_helix =>
          exists bk_helix,
            memory_lookup mem_helix ptr_helix ≡ Some bk_helix /\
            exists ptr_llvm bk_llvm,
              in_local_or_global ι ρ g x (DVALUE_Addr ptr_llvm) /\
              get_logical_block (fst mem_llvm) ptr_llvm ≡ Some bk_llvm /\
              (fun bk_helix bk_llvm =>
                 forall i, Int64.lt i ptr_size_helix ->
                      exists v_helix v_llvm,
                        mem_lookup (MInt64asNT.to_nat i) bk_helix ≡ Some v_helix /\
                        mem_lookup_llvm_at_i bk_llvm (MInt64asNT.to_nat i)
                                             (MInt64asNT.to_nat ptr_size_helix) v_llvm /\
                        v_llvm ≡ UVALUE_Double v_helix
              ) bk_helix bk_llvm
        end.

(**
   Lifting of [memory_invariant] to include return values in the relation.
   This relation is used to prove the correctness of the compilation of operators.
   The value on the Helix side is trivially [unit]. The value on the Vellvm-side however
   is non trivial, we will most likely have to mention it.
*)
(* TODO: Currently this relation just preserves memory invariant.
   Maybe it needs to do something more?
 *)
Definition bisim_partial: Type_R_partial
  :=
    fun σ '(mem_helix, _) '(mem_llvm, x) =>
      let '(ρ, (g, bid_or_v)) := x in
      memory_invariant σ mem_helix (mem_llvm, (ρ, g)).

(**
   Relation over memory and invariant for a full [cfg], i.e. to relate states at
   the top-level.
   Currently a simple lifting of [bisim_partial].
*)
Definition bisim_full: Type_R_full  :=
  fun σ  '(mem_helix, v_helix) mem_llvm =>
    let '(m, ((ρ,_), (g, v))) := mem_llvm in
    bisim_partial σ (mem_helix, tt) (mk_LLVM_state_cfg_from_mem (inr v) (m, (ρ, g))).


(** Relation bewteen the final states of evaluation and execution
    of DHCOL program.

    At this stage we do not care about memory or environemnts, and
    just compare return value of [main] function in LLVM with
    evaulation results of DSHCOL.
 *)
Definition bisim_final: Type_R_full :=
  fun σ '(_, h_result) '(_,(_,(_,llvm_result))) =>
    match llvm_result with
    | UVALUE_Array arr => @List.Forall2 _ _
                                       (fun ve de =>
                                          match de with
                                          | UVALUE_Double d =>
                                            Floats.Float.cmp Integers.Ceq d ve
                                          | _ => False
                                          end)
                                       h_result arr
    | _ => False
    end.

End SimulationRelations.

(* begin tactics *)

(* TODOYZ: This is a redefinition from [DSigmaHCOLITree]. To remove after proper reorganization into two files *)
(* TODOYZ: Actually even more so there should be a clean part of the tactics that do the generic structural
   rewriting, and a wrapper around it doing stuff specific to this denotation. We should only need the former
   here I believe *)
Ltac inv_mem_lookup_err :=
  unfold mem_lookup_err, trywith in *;
  break_match_hyp; cbn in *; try (inl_inr || inv_sum || inv_sum).

Ltac inv_memory_lookup_err :=
  unfold memory_lookup_err, trywith in *;
  break_match_hyp; cbn in *; try (inl_inr || inv_sum || inv_sum).


Ltac state_steps :=
  cbn;
  repeat (
      ((match goal with
        | |- ITree.bind (lift_Derr _) _ ≈ _ => break_match_goal; inv_memory_lookup_err; inv_option
        | |- ITree.bind (lift_Serr _) _ ≈ _ => break_match_goal; inv_memory_lookup_err; inv_option
        | |- ITree.bind (State.interp_state _ (lift_Derr _) _) _ ≈ _ => break_match_goal; inv_option
        | |- ITree.bind (State.interp_state _ (lift_Serr _) _) _ ≈ _ => break_match_goal; inv_option
        end) || state_step); cbn).

Ltac eutt_hide_left :=
  match goal with
    |- eutt _ ?t _ => remember t
  end.

Ltac eutt_hide_right :=
  match goal with
    |- eutt _ _ ?t => remember t
  end.

Ltac eutt_hide_rel :=
  match goal with
    |- eutt ?r _ _ => remember r
  end.

Ltac hide_string_goal :=
  match goal with
  | |- context [String ?x ?y] => remember (String x y)
  end.

Ltac hide_string_hyp H :=
  match type of H with
  | context [String ?x ?y] => remember (String x y)
  end.

Ltac hide_strings :=
  repeat (
      match goal with
      | h: context [String ?x ?y] |- _ => remember (String x y)
      | |- context [String ?x ?y] => remember (String x y)
      end).

(* end tactics *)

Section Add_Comment.

  (* NOTEYZ:
     Move this or a similar facility to Vellvm
   *)
  Lemma add_comment_preserves_num_blocks :
    forall l comments blocks,
      add_comment l comments ≡ blocks ->
      List.length l ≡ List.length blocks.
  Proof.
    induction l; intros comments blocks H.
    - inversion H; reflexivity.
    - simpl. inversion H. simpl.
      reflexivity.
  Qed.

  Lemma add_comment_singleton :
    forall l comments block,
      add_comment l comments ≡ [block] ->
      exists b, l ≡ [b].
  Proof.
    intros l comments block H.
    destruct l.
    - inv H.
    - destruct l.
      + exists b. reflexivity.
      + inv H.
  Qed.

End Add_Comment.

Section InterpMem.

  Lemma interp_Mem_ret :
    forall T mem x,
      @interp_Mem T (Ret x) mem ≅ Ret (mem, x).
  Proof.
    intros T mem x.
    unfold interp_Mem.
    apply interp_state_ret.
  Qed.

  Lemma interp_Mem_bind :
    forall T U mem (t: itree Event T) (k: T -> itree Event U),
      interp_Mem (ITree.bind t k) mem ≈ ITree.bind (interp_Mem t mem) (fun '(mem',v) => interp_Mem (k v) mem').
  Proof.
    intros; unfold interp_Mem.
    rewrite interp_state_bind.
    apply eutt_eq_bind; intros []; reflexivity.
  Qed.

  Lemma interp_Mem_vis_eqit :
    forall T R mem (e : Event T) (k : T -> itree Event R),
      interp_Mem (vis e k) mem ≅ ITree.bind ((case_ Mem_handler MDSHCOLOnFloat64.pure_state) T e mem) (fun sx => Tau (interp_Mem (k (snd sx)) (fst sx))).
  Proof.
    intros T R mem e k.
    unfold interp_Mem.
    apply interp_state_vis.
  Qed.

  (* Lemma interp_Mem_trigger : *)
  (*   forall T R mem (e : Event T) (k : T -> itree Event R), *)
  (*     interp_Mem (ITree.bind (trigger e) k) mem ≈ ITree.bind ((case_ Mem_handler MDSHCOLOnFloat64.pure_state) T e mem) (fun sx => interp_Mem (k (snd sx)) (fst sx)). *)
  (* Proof. *)
  (*   intros T R mem e k. *)
  (*   unfold interp_Mem. *)
  (*   apply interp_state_vis. *)
  (* Qed. *)


  Lemma interp_Mem_MemLU_vis :
    forall R str mem m x (k : _ -> itree _ R),
      memory_lookup_err str mem x ≡ inr m ->
      interp_Mem (vis (MemLU str x) k) mem ≈ interp_Mem (k m) mem.
  Proof.
    intros R str mem m x k H.
    setoid_rewrite interp_Mem_vis_eqit;
      cbn; rewrite H; cbn.
    rewrite bind_ret_l; cbn.
    apply tau_eutt.
  Qed.

  Lemma interp_Mem_MemLU :
    forall str mem m x,
      memory_lookup_err str mem x ≡ inr m ->
      interp_Mem (trigger (MemLU str x)) mem ≈ interp_Mem (Ret m) mem.
  Proof.
    intros str mem m x H.
    unfold trigger.
    rewrite interp_Mem_MemLU_vis; eauto.
    reflexivity.
  Qed.

  Lemma interp_Mem_MemSet :
    forall dst blk mem,
      interp_Mem (trigger (MemSet dst blk)) mem ≈ Ret (memory_set mem dst blk, ()).
  Proof.
    intros dst blk mem.
    setoid_rewrite interp_Mem_vis_eqit; cbn.
    rewrite bind_ret_l.
    rewrite interp_Mem_ret.
    apply tau_eutt.
  Qed.

End InterpMem.

  Ltac unfolder_vellvm := unfold Traversal.Endo_id, translate_E_vellvm_cfg.
  Ltac unfolder_vellvm_hyp h := unfold Traversal.Endo_id, translate_E_vellvm_cfg in h.
    (* unfold lookup_E_to_exp_E,exp_E_to_instr_E. *)

  Ltac unfolder_helix := unfold ErrorWithState.option2errS, translate_E_helix_cfg, lift_Serr.
  Ltac unfolder_helix_hyp h := unfold ErrorWithState.option2errS, translate_E_helix_cfg, lift_Serr in h.

  (**
     Better solution (?): use
     `Argument myconstant /.`
     to force `cbn` to unfold `myconstant`
   *)
  Tactic Notation "unfolder" := unfolder_helix; unfolder_vellvm.
  Tactic Notation "unfolder" "in" hyp(h) := unfolder_helix_hyp h; unfolder_vellvm_hyp h.

  Tactic Notation "cbn*" := (repeat (cbn; unfolder)).
  Tactic Notation "cbn*" "in" hyp(h) := (repeat (cbn in h; unfolder in h)).

  (** **
      TODO YZ : This needs to leave other hypotheses that H untouched
   *)
  Ltac simp_comp H :=
    cbn in H; unfolder in H;
    cbn in H; repeat (inv_sum || break_and || break_match_hyp).

  Lemma subevent_subevent : forall {E F} `{E -< F} {X} (e : E X),
      @subevent F F _ X (@subevent E F _ X e) ≡ subevent X e.
  Proof.
    reflexivity.
  Qed.

  (* We associate [bind]s to the right and dismiss leftmost [Ret]s *)
  (* NOTE YZ :
     To help debugging this automation, tactics take an argument [k] representing a boolean flag as an integer.
     I use [do k] to print debug messages if [k=1].
     I then define two tactic notation [tac] and [tacD] setting the flag to 0 and 1 respectively.
     Question: is there anyway to avoid having to define an intermediate notation just to force k to be parsed as an integer
     rather than a constr?
   *)
  (* TODO YZ :
     Can we avoid the duplication of the tactics into a version for hypotheses and one for goals by being able
     to take a pattern of the form that rewrite admits?
   *)
  Ltac norm_monad_k t k :=
    match t with
    | context[ITree.bind ?t' _] =>
      match t' with
      | ITree.bind _ _ => rewrite bind_bind ;
                         do k idtac "bind_bind"
      | Ret _ => rewrite bind_ret_l ;
                do k idtac "bind_ret"
      end
    end.

  Tactic Notation "norm_monad_k'" constr(t) integer(k) := norm_monad_k t k.
  Tactic Notation "norm_monad" constr(t) := norm_monad_k' t 0.
  Tactic Notation "norm_monadD" constr(t) := norm_monad_k' t 1.

  (* Normalization in an hypothesis h instead of the goal *)
  Ltac norm_monad_hyp_k t h k :=
    match t with
    | context[ITree.bind ?t' _] =>
      match t' with
      | ITree.bind _ _ => rewrite bind_bind in h ; do k idtac "bind_bind"
      | Ret _ => rewrite bind_ret_l in h ; do k idtac "bind_ret"
      end
    end.

  Tactic Notation "norm_monad_hyp_k'" constr(t) hyp(h) integer(k) := norm_monad_hyp_k t h k.
  Tactic Notation "norm_monad_hyp" constr(t) hyp(h) := norm_monad_hyp_k' t h 0.
  Tactic Notation "norm_monad_hypD" constr(t) hyp(h) := norm_monad_hyp_k' t h 1.

  (* We push [translate]s and [interp]s inside of binds, run them through [Ret]s *)
  Ltac norm_interp_k t k :=
    match t with
    | context[translate _ (ITree.bind ?t' _)] => rewrite translate_bind ; do k idtac "trans_bind"
    | context[interp _ (ITree.bind ?t' _)] => rewrite interp_bind ; do k idtac "interp_bind"
    | context[translate _ (Ret _)] => rewrite translate_ret ; do k idtac "trans_ret"
    | context[interp _ (Ret _)] => rewrite interp_ret ; do k idtac "interp_ret"
    | context[translate _ (trigger ?e)] => rewrite (translate_trigger _ e) ; do k idtac "trans_trigger"
    | context[interp _ (trigger _)] => rewrite interp_trigger ; do k idtac "intepr_trigger"
    end.

  Tactic Notation "norm_interp_k'" constr(t) integer(k) := norm_interp_k t k.
  Tactic Notation "norm_interp" constr(t) := norm_interp_k' t 0.
  Tactic Notation "norm_interpD" constr(t) := norm_interp_k' t 1.

  Ltac norm_interp_hyp_k t h k :=
    match t with
    | context[translate _ (ITree.bind ?t' _)] => rewrite translate_bind in h ; do k idtac "trans_bind"
    | context[interp _ (ITree.bind ?t' _)] => rewrite interp_bind in h ; do k idtac "interp_bind"
    | context[translate _ (Ret _)] => rewrite translate_ret in h ; do k idtac "trans_ret"
    | context[interp _ (Ret _)] => rewrite interp_ret in h ; do k idtac "interp_ret"
    | context[translate _ (trigger ?e)] => rewrite (translate_trigger _ e) in h ; do k idtac "trans_trigger"
    | context[interp _ (trigger _)] => rewrite interp_trigger in h ; do k idtac "intepr_trigger"
    end.

  Tactic Notation "norm_interp_hyp_k'" constr(t) hyp(h) integer(k) := norm_interp_hyp_k t h k.
  Tactic Notation "norm_interp_hyp" constr(t) hyp(h) := norm_interp_hyp_k' t h 0.
  Tactic Notation "norm_interp_hypD" constr(t) hyp(h) := norm_interp_hyp_k' t h 1.

  (* We extend [norm_interp] with locally defined interpreters on the helix side *)
  Ltac norm_local_helix_k t k :=
    match t with
    | context[interp_Mem (ITree.bind ?t' _)] => rewrite interp_Mem_bind ; do k idtac "mem_bind"
    | context[interp_Mem (Ret _)] => rewrite interp_Mem_ret ; do k idtac "mem_ret"
    | context[interp_Mem (trigger (MemLU _ _)) _] =>
      rewrite interp_Mem_MemLU; do k idtac "mem_memlu"
    end.

  Tactic Notation "norm_local_helix_k'" constr(t) integer(k) := norm_local_helix_k t k.
  Tactic Notation "norm_local_helix" constr(t) := norm_local_helix_k' t 0.
  Tactic Notation "norm_local_helixD" constr(t) := norm_local_helix_k' t 1.

  Ltac norm_local_helix_hyp_k t h k :=
    match t with
    | context[interp_Mem (ITree.bind ?t' _)] => rewrite interp_Mem_bind in h ; do k idtac "mem_bind"
    | context[interp_Mem (Ret _)] => rewrite interp_Mem_ret in h ; do k idtac "mem_ret"
    end.

  Tactic Notation "norm_local_helix_hyp_k'" constr(t) hyp(h) integer(k) := norm_local_helix_hyp_k t h k.
  Tactic Notation "norm_local_helix_hyp" constr(t) hyp(h) := norm_local_helix_hyp_k' t h 0.
  Tactic Notation "norm_local_helix_hypD" constr(t) hyp(h) := norm_local_helix_hyp_k' t h 1.

  (* We extend [norm_interp] with locally defined interpreters on the vellvm side *)
  Ltac norm_local_vellvm_k t k :=
    match t with
    | context[interp_cfg_to_L3 _ (ITree.bind ?t' _)] => rewrite interp_cfg_to_L3_bind ; do k idtac "cfg_bind"
    | context[interp_cfg_to_L3 _ (Ret _)] => rewrite interp_cfg_to_L3_ret ; do k idtac "cfg_ret"
    | context[interp_cfg_to_L3 _ (trigger (GlobalRead _))] => rewrite interp_cfg_to_L3_GR ; do k idtac "cfg_GR"
    | context[interp_cfg_to_L3 _ (trigger (LocalRead _))] => rewrite interp_cfg_to_L3_LR ; do k idtac "cfg_LR"
    | context[lookup_E_to_exp_E (subevent _ _)] => (rewrite lookup_E_to_exp_E_Global || rewrite lookup_E_to_exp_E_Local); try rewrite subevent_subevent ; do k idtac "luexp"
    | context[exp_E_to_instr_E (subevent _ _)] => (rewrite exp_E_to_instr_E_Global || rewrite exp_E_to_instr_E_Local); try rewrite subevent_subevent ; do k idtac "expinstr"
    end.

  Tactic Notation "norm_local_vellvm_k'" constr(t) integer(k) := norm_local_vellvm_k t k.
  Tactic Notation "norm_local_vellvm" constr(t) := norm_local_vellvm_k' t 0.
  Tactic Notation "norm_local_vellvmD" constr(t) := norm_local_vellvm_k' t 1.

  Ltac norm_local_vellvm_hyp_k t h k :=
    match t with
    | context[interp_cfg_to_L3 _ (ITree.bind ?t' _)] => rewrite interp_cfg_to_L3_bind in h ; do k idtac "cfg_bind"
    | context[interp_cfg_to_L3 _ (Ret _)] => rewrite interp_cfg_to_L3_ret in h ; do k idtac "cfg_ret"
    | context[interp_cfg_to_L3 _ (trigger (GlobalRead _))] => rewrite interp_cfg_to_L3_GR in h ; do k idtac "cfg_GR"
    | context[interp_cfg_to_L3 _ (trigger (LocalRead _))] => rewrite interp_cfg_to_L3_LR in h ; do k idtac "cfg_LR"
    | context[lookup_E_to_exp_E (subevent _ _)] => (rewrite lookup_E_to_exp_E_Global in h || rewrite lookup_E_to_exp_E_Local in h); try rewrite subevent_subevent in h ; do k idtac "luexp"
    | context[exp_E_to_instr_E (subevent _ _)] => (rewrite exp_E_to_instr_E_Global in h || rewrite exp_E_to_instr_E_Local in h); try rewrite subevent_subevent in h ; do k idtac "expinstr"
    end.

  Tactic Notation "norm_local_vellvm_hyp_k'" constr(t) hyp(h) integer(k) := norm_local_vellvm_hyp_k t h k.
  Tactic Notation "norm_local_vellvm_hyp" constr(t) hyp(h) := norm_local_vellvm_hyp_k' t h 0.
  Tactic Notation "norm_local_vellvmD" constr(t) hyp(h) := norm_local_vellvm_hyp_k' t h 1.

  (**
     QUESTION YZ: the outer repeat does not have any effect. Why and how to fix?
   *)
  Ltac norm_h_k k :=
    match goal with
      |- eutt _ ?t _ =>
      repeat (
          repeat (norm_monad_k t k);
          repeat (norm_interp_k t k);
          repeat (norm_local_helix_k t k))
    end.
  Tactic Notation "norm_h_k'" integer(k) := norm_h_k k.
  Tactic Notation "norm_h" := norm_h_k' 0.
  Tactic Notation "norm_hD" := norm_h_k' 1.

  Ltac norm_h_hyp_k h k :=
    match type of h with
      eutt _ ?t _ =>
      repeat (
          repeat (norm_monad_hyp_k t h k);
          repeat (norm_interp_hyp_k t h k);
          repeat (norm_local_helix_hyp_k t h k))
    end.
  Tactic Notation "norm_h_hyp_k'" hyp(h) integer(k) := norm_h_hyp_k h k.
  Tactic Notation "norm_h" "in" hyp(h) := norm_h_hyp_k' h 0.
  Tactic Notation "norm_hD" "in" hyp(h) := norm_h_hyp_k' h 1.

  Ltac norm_v_k k :=
    match goal with
      |- eutt _ _ ?t =>
      repeat (
          repeat (norm_monad_k t k);
          repeat (norm_interp_k t k);
          repeat (norm_local_vellvm_k t k))
    end.
  Tactic Notation "norm_v_k'" integer(k) := norm_v_k k.
  Tactic Notation "norm_v" := norm_v_k' 0.
  Tactic Notation "norm_vD" := norm_v_k' 1.

  Ltac norm_v_hyp_k h k :=
    match type of h with
      eutt _ _ ?t =>
      repeat (
          repeat (norm_monad_hyp_k t h k);
          repeat (norm_interp_hyp_k t h k);
          repeat (norm_local_vellvm_hyp_k t h k))
    end.

  Tactic Notation "norm_v_hyp_k'" hyp(h) integer(k) := norm_v_hyp_k h k.
  Tactic Notation "norm_v" "in" hyp(h) := norm_v_hyp_k' h 0.
  Tactic Notation "norm_vD" "in" hyp(h) := norm_v_hyp_k' h 1.

Section NExpr.

  (**
     We prove in this section the correctness of the compilation of numerical expressions, i.e. [NExpr].
     The corresponding compiling function is [genNExpr].

     Helix side:
     * nexp: NExpr
     * σ: evalContext
     * s: IRState

The expression must be closed in [evalContext]. I.e. all variables are below the length of σ
vars s1 = σ?

   *)
  (* NOTEYZ:
     These expressions are pure. As such, it is true that we do not need to interpret away
     the memory events on Helix side to establish the bisimulation.
     However at least in the current state of affair, I believe it's widely more difficult
     to lift the result before interpretation to the context we need than to simply plug in
     the interpreter.
     In particular we would need to have a clean enough lift that deduces that the memory has
     not been modified. I'm interested in having this, but I do not know how easy it is to get it.
     TODOYZ: Investigate this claim
   *)
  Opaque interp_Mem.
  Opaque append.

  Ltac break_and :=
    repeat match goal with
           | h: _ * _ |- _ => destruct h
           end.

  Definition genNExpr_sim σ := (bisim_partial σ).

  (**
     NOTEYZ: It is slightly annoying that [IRState] is an extra piece of state introduced by
     the compiler by that belongs to neither language.
     Invariants about it must therefore be carried separately from the simulation relation.
   *)

  (**
     Relational injection of [DSHType] into VIR's [typ]
     TODOYZ : Well, precisely, todo.
     OBSOLETE: replaced by [getIRType]
   *)
  (* Variant DSHType_typ : DSHType -> typ -> Prop := *)
  (* | DSHnat_IntType : DSHType_typ DSHnat IntType *)
  (**
     The compiler maintains a sort of typing context named [IRState].
     It should be essentially a well-formed typing judgment for the current
     value of the [evalContext], but injecting the types from [DSHCOL] to [VIR].
   *)
  Definition WF_IRState (σ: evalContext) (s: IRState): Prop :=
    forall (i: ident) (t: typ) (n: nat),
      nth_error (vars s) n ≡ Some (i,t) ->
      exists (v: DSHVal), nth_error σ n ≡ Some v /\
                     getIRType (DSHType_of_DSHVal v) ≡ t.

  Lemma WF_IRState_lookup_cannot_fail :
    forall σ it s n msg msg',
      WF_IRState σ s ->
      nth_error (vars s) n ≡ Some it ->
      context_lookup msg σ n ≡ inl msg' ->
      False.
  Proof.
    intros ? [] * WF LU1 LU2; apply WF in LU1; destruct LU1 as (? & LU & _).
    unfold context_lookup in LU2; rewrite LU in LU2; inversion LU2.
  Qed.

  Lemma WF_IRState_lookup_int :
    forall σ s n id msg,
      WF_IRState σ s ->
      nth_error (vars s) n ≡ Some (id,TYPE_I 64%Z) ->
      exists v, context_lookup msg σ n ≡ inr (DSHnatVal v).
  Proof.
    intros * WF LU; apply WF in LU; destruct LU as ([] & LU & EQ);
      unfold context_lookup; rewrite LU; cbn; try inv EQ.
    eexists; reflexivity.
  Qed.

  Lemma WF_IRState_lookup_pointer :
    forall σ s n id,
      WF_IRState σ s ->
      nth_error (vars s) n ≡ Some (id,TYPE_Pointer (TYPE_I 64%Z)) ->
      False.
  Proof.
    intros * WF LU; apply WF in LU; destruct LU as ([] & LU & EQ); inv EQ.
  Qed.

  Ltac abs_by H :=
    exfalso; eapply H; eauto.

  (* TODOYZ : MOVE *)
  Definition conj_rel {A B : Type} (R S: A -> B -> Prop): A -> B -> Prop :=
    fun a b => R a b /\ S a b.
  Infix "⩕" := conj_rel (at level 85).

  Variable (R: Type_R_memory_cfg).
  Definition R' : Int64.int -> uvalue -> Prop :=
    fun i uv => uv ≡ UVALUE_I64 i.
  (* R, R' to be instantiated *)

  (* Facts that must be derivable *)
  Axiom R_GLU : forall σ s v id memH memV l g n,
  WF_IRState σ s ->
  nth_error (vars s) v ≡ Some (ID_Global id, TYPE_I 64%Z) ->
  R σ memH (memV, (l, g)) ->
  context_lookup "NVar not found" σ v ≡ inr (DSHnatVal n) ->
  Maps.lookup id g ≡ Some (DVALUE_I64 n).

  Axiom R_LLU : forall σ s v id memH memV l g n,
  WF_IRState σ s ->
  nth_error (vars s) v ≡ Some (ID_Local id, TYPE_I 64%Z) ->
  R σ memH (memV, (l, g)) ->
  context_lookup "NVar not found" σ v ≡ inr (DSHnatVal n) ->
  Maps.lookup id l ≡ Some (UVALUE_I64 n).

  (**
     QUESTION YZ: Works okay (though slow), except for [ret/Ret], a cbn or an unfold needs to be sneaked in the right place

     TODO YZ : add that the returned IRState is also WF
   *)

  Set Nested Proofs Allowed.

  Lemma WFevalNexp_succeed:
    forall nexp s s' σ x,
      WF_IRState σ s ->
      genNExpr nexp s ≡ inr (s',x) ->
      WF_IRState σ s'.
  Proof.
    induction nexp; intros * WF GEN; simp_comp GEN; auto.
    all: eapply IHnexp1 in Heqs0; eapply IHnexp2 in Heqs1; eauto.
  Qed.

  Lemma WFevalNexp_no_fail:
    forall nexp s σ x msg,
      WF_IRState σ s ->
      genNExpr nexp s ≡ inr x ->
      evalNExpr σ nexp ≡ inl msg ->
      False.
  Proof.
    induction nexp; cbn; intros * WF COMP EVAL;
      try now (simp_comp COMP; cbn in *; try inv_sum).
    - unfold context_lookup, trywith in *.
      cbn in COMP; unfolder in COMP; cbn in COMP.
      simp_comp COMP; cbn in *; try inv_sum;
        edestruct WF as (? & ? & ?); eauto.
      all:try match goal with
              | [h : ?x ≡ _ , h' : ?x ≡ _ |- _] => rewrite h in h'; inv h'
              end.
      all: match goal with
           | h: getIRType _ ≡ _ |- _ => inv h
           end.
    - simp_comp COMP; cbn in *; try inv_sum.
      eapply IHnexp1; eauto.
      eapply IHnexp2; [eapply WFevalNexp_succeed | ..]; eauto.
    - simp_comp COMP; cbn in *; try inv_sum.
      eapply IHnexp1; eauto.
      eapply IHnexp2; [eapply WFevalNexp_succeed | ..]; eauto.
    - simp_comp COMP; cbn in *; try inv_sum.
      eapply IHnexp1; eauto.
      eapply IHnexp2; [eapply WFevalNexp_succeed | ..]; eauto.
    - simp_comp COMP; cbn in *; try inv_sum.
      eapply IHnexp1; eauto.
      eapply IHnexp2; [eapply WFevalNexp_succeed | ..]; eauto.
    - simp_comp COMP; cbn in *; try inv_sum.
      eapply IHnexp1; eauto.
      eapply IHnexp2; [eapply WFevalNexp_succeed | ..]; eauto.
  Qed.

  (* TODO move to Vellvm/Tactics *)
  Ltac ret_bind_l_left v :=
    match goal with
      |- eutt _ ?t _ =>
      rewrite <- (bind_ret_l v (fun _ => t))
    end.

  (* TODO MOVE *)
  Lemma convert_typ_app : ∀ (a b : code typ) env, (convert_typ env (a ++ b) ≡ convert_typ env a ++ convert_typ env b)%list.
  Proof.
    induction a as [| [] a IH]; cbn; intros; auto.
    rewrite IH; reflexivity.
  Qed.

  (** YZ
      At the top level, the correctness of genNExpr is expressed as the denotation of the operator being equivalent
      to the bind of denoting the code followed by denoting the expression.
      However this is not inductively stable, we only want to plug the expression at the top level.
      We therefore instead carry the fact about the denotation of the expression in the invariant. (Is there another clever way?)
      TODO: how to make this (much) less ugly?
   *)
  Definition R'' (e: exp typ) : Type_R_cfg_T DynamicValues.int64 unit :=
    fun s '(_,i) '(memV,(l,(g,_))) =>
      Ret (memV,(l,(g,UVALUE_I64 i))) ≈
          translate_E_vellvm_cfg
          (interp_cfg_to_L3 helix_intrinsics (translate exp_E_to_instr_E (denote_exp (Some (DTYPE_I 64%Z)) (convert_typ [] e))) g l memV).

  Definition memory_invariant_MCFG: Type_R_mcfg_T unit unit :=
    fun σ '(memH,_) '(memV,((l,sl),(g,_))) =>
      memory_invariant σ memH (memV,(l,g)).

  Definition memory_invariant_memory_mcfg: Type_R_memory_mcfg :=
    fun σ memH '(memV,((l,sl),g)) =>
      memory_invariant σ memH (memV,(l,g)).

  (* TODO YZ : Move to itrees *)
  (* Simple specialization of [eqit_Ret] to [eutt] so that users of the library do not need to know about [eqit] *)
  Lemma eutt_Ret :
    forall E (R1 R2 : Type) (RR : R1 -> R2 -> Prop) r1 r2, RR r1 r2 <-> eutt (E := E) RR (Ret r1) (Ret r2).
  Proof.
    intros; apply eqit_Ret.
  Qed.

  (* TODO YZ : Move to itrees *)
  (* Specialization of [eutt_clo_bind] to the case where the intermediate predicate introduced is the same as the current one *)
  Lemma eutt_bind_Inv :
    ∀ (E : Type → Type) (R1 R2 : Type) (RR : R1 → R2 → Prop) (t1 : itree E R1) (t2 : itree E R2)
      (k1 : R1 → itree E R1) (k2 : R2 → itree E R2),
      eutt RR t1 t2 →
      (∀ (r1 : R1) (r2 : R2), RR r1 r2 → eutt RR (k1 r1) (k2 r2)) →
      eutt RR (ITree.bind t1 (λ x : R1, k1 x)) (ITree.bind t2 (λ x : R2, k2 x)).
  Proof.
    intros; apply eutt_clo_bind with (UU := RR); auto.
  Qed.

  (* TODO YZ : move to Vellvm *)
  Ltac simpl_match_hyp h :=
    match type of h with
      context[match ?x with | _ => _ end] =>
      match goal with
      | EQ: x ≡ _ |- _ => rewrite EQ in h
      | EQ: _ ≡ x |- _ => rewrite <- EQ in h
      end
    end.
  Tactic Notation "simpl_match" "in" hyp(h) := simpl_match_hyp h.

  Ltac introR :=
    intros [?memH ?vH] (?memV & ?l & ?g & ?vV) ?PRE.
  Ltac destruct_unit :=
    match goal with
    | x : unit |- _ => destruct x
    end.

  Lemma genNExpr_correct_ind :
    forall (* Compiler bits *) (s1 s2: IRState)
      (* Helix  bits *)   (nexp: NExpr) (σ: evalContext) (memH: memoryH)
      (* Vellvm bits *)   (e: exp typ) (c: code typ) (g : global_env) (l : local_env) (memV : memoryV),
      genNExpr nexp s1 ≡ inr (s2, (e, c)) -> (* Compilation succeeds *)
      WF_IRState σ s1 ->                     (* Well-formed IRState *)
      R σ memH (memV, (l, g)) ->
      (* (WF_IRState σ s2 /\ *)
       eutt (lift_R_memory_cfg R σ ⩕ R'' e σ)
            (translate_E_helix_cfg
               (interp_Mem (denoteNExpr σ nexp)
                           memH))
            (translate_E_vellvm_cfg
               (interp_cfg_to_L3 helix_intrinsics
                                  (denote_code (convert_typ [] c))
                  g l memV)).
  Proof.
    intros s1 s2 nexp; revert s1 s2; induction nexp; intros * COMPILE WFIR PRE;
      assert (FOO: (s2,(exp,c)) ≡ (s2,(exp,c))) by reflexivity. (* TODOYZ: stupid hack to quickly check what case we are in. To remove *)
    - (* Variable case *)
      (* Reducing the compilation *)
      (* simp_comp COMPILE; (split; [auto |]). *)
      simp_comp COMPILE.

      + (* The variable maps to an integer in the IRState *)
        unfold denoteNExpr; cbn*.

        repeat norm_v.
        break_inner_match_goal.
        * (* Variable not in context, [context_lookup] fails *)
          abs_by WF_IRState_lookup_cannot_fail.
        * break_inner_match_goal.
          ++ repeat norm_h.
             destruct i0.
             { (* Global *)
               apply eutt_Ret; split.
               apply PRE.
               unfold R''; cbn*.
               repeat norm_v.
               cbn; repeat norm_v.
               2: eapply R_GLU; eauto.
               reflexivity.
             }
             { (* Local *)
               apply eutt_Ret.
               split; [apply PRE | ].
               cbn*. repeat norm_v.
               2: eapply R_LLU; eauto.
               cbn; repeat norm_v.
               reflexivity.
             }
          ++
            (** TODO YZ : get this automatically discharged by [abs_by] *)
            exfalso. eapply WF_IRState_lookup_int in WFIR; eauto.
            destruct WFIR as [? WFIR]; rewrite Heqs in WFIR; inv WFIR.
          ++
            exfalso. eapply WF_IRState_lookup_int in WFIR; eauto.
            destruct WFIR as [? WFIR]; rewrite Heqs in WFIR; inv WFIR.

      + (* The variable maps to a pointer *)
        abs_by WF_IRState_lookup_pointer.

    - (* Constant *)

      simp_comp COMPILE(* ; split; auto *).
      unfold denoteNExpr; cbn*.
      repeat norm_h.
      repeat norm_v.
      apply eutt_Ret.
      split; [apply PRE |].
      cbn*; rewrite repr_intval; repeat norm_v.
      reflexivity.

    - (* NDiv *)

      simp_comp COMPILE.

      generalize Heqs; intros WFI; eapply WFevalNexp_succeed in WFI; eauto.

      eutt_hide_right.
      unfold denoteNExpr in *; cbn*.

      break_inner_match_goal; [| break_inner_match_goal].
      + clear - Heqs Heqs1 WFIR; abs_by WFevalNexp_no_fail.
      + clear - Heqs0 WFI Heqs2; abs_by WFevalNexp_no_fail.
      + repeat norm_h.

        (* TODO YZ: gets some super specialize tactics that do not require to provide variables *)
        specialize (IHnexp1 _ _ _ _ _ _ _ _ _ Heqs WFIR PRE).

        (* TODO YZ : unfolderH is not doing all the work, fix *)
        unfold translate_E_vellvm_cfg in IHnexp1; cbn* in IHnexp1;
          repeat norm_v in IHnexp1;
          repeat norm_h in IHnexp1.
        simpl_match in IHnexp1.
        (* YZ TODO : Why is this one particularly slow? *)
        repeat norm_h in IHnexp1.

        subst.
        eutt_hide_left.
        cbn*.
        rewrite convert_typ_app, denote_code_app.
        repeat norm_v.
        subst.
        ret_bind_l_left (memH,i2).
        eapply eutt_clo_bind; [eassumption |].

        introR; destruct_unit.
        destruct PRE0 as [PRE0 HR''].
        specialize (IHnexp2 _ _ _ _ _ _ _ _ _ Heqs0 WFI PRE0).

        unfold translate_E_vellvm_cfg in IHnexp2; cbn* in IHnexp2;
          repeat norm_v in IHnexp2;
          repeat norm_h in IHnexp2.
        simpl_match in IHnexp2.
        repeat norm_h in IHnexp2.

        eutt_hide_left.
        rewrite convert_typ_app, denote_code_app.
        repeat norm_v.
        subst.
        ret_bind_l_left (memH0,i3).
        eapply eutt_clo_bind; [eassumption |].

        introR; destruct_unit.
        destruct PRE1 as [PRE1 ?HR''].

        simpl.
        norm_v.
        norm_v.
        norm_v.
        (* YZ TODO specialized tactic to use the same current value *)
        ret_bind_l_left (memH,MInt64asNT.NTypeDiv i2 i3).
        eutt_hide_rel; eutt_hide_left.


        (* TODO YZ : rename [eval_op] to [denote_op] *)
        unfold eval_op.
        simpl denote_exp.
        admit.

    - admit.

    - (* NAdd *)

      simp_comp COMPILE.
      clear FOO.

      (* YZ TODO Ltac for this *)
      generalize Heqs; intros WFI; eapply WFevalNexp_succeed in WFI; eauto.

      eutt_hide_right.
      unfold denoteNExpr in *; cbn*.

      break_inner_match_goal; [| break_inner_match_goal].
      + clear - Heqs Heqs1 WFIR; abs_by WFevalNexp_no_fail.
      + clear - Heqs0 WFI Heqs2; abs_by WFevalNexp_no_fail.
      + repeat norm_h.

        (* TODO YZ: gets some super specialize tactics that do not require to provide variables *)
        specialize (IHnexp1 _ _ _ _ _ _ _ _ _ Heqs WFIR PRE).

        (* TODO YZ : unfolderH is not doing all the work, fix *)
        unfold translate_E_vellvm_cfg in IHnexp1; cbn* in IHnexp1;
          repeat norm_v in IHnexp1;
          repeat norm_h in IHnexp1.
        simpl_match in IHnexp1.
        (* YZ TODO : Why is this one particularly slow? *)
        repeat norm_h in IHnexp1.

        subst.
        eutt_hide_left.
        cbn*.
        rewrite convert_typ_app, denote_code_app.
        repeat norm_v.
        subst.
        ret_bind_l_left (memH,i2).
        eapply eutt_clo_bind; [eassumption |].

        introR; destruct_unit.
        destruct PRE0 as [PRE0 HR''].
        specialize (IHnexp2 _ _ _ _ _ _ _ _ _ Heqs0 WFI PRE0).

        unfold translate_E_vellvm_cfg in IHnexp2; cbn* in IHnexp2;
          repeat norm_v in IHnexp2;
          repeat norm_h in IHnexp2.
        simpl_match in IHnexp2.
        repeat norm_h in IHnexp2.

        eutt_hide_left.
        rewrite convert_typ_app, denote_code_app.
        repeat norm_v.
        subst.
        ret_bind_l_left (memH0,i3).
        eapply eutt_clo_bind; [eassumption |].

        introR; destruct_unit.
        destruct PRE1 as [PRE1 ?HR''].

        (* Just for debugging *)
        rename i0 into s3, e1 into e2, c1 into c2.
        rename i into s2, e0 into e1, c0 into c1.
        rename i2 into i1, i3 into i2.
        rename memV0 into memV2, l0 into l2, g0 into g2.
        rename memV1 into memV3, l1 into l3, g1 into g3.
        rename memV into memV1, l into l1, g into g1.



        (* YZ CHECKPOINT :
           Confused at the moment: the subexpressions seem to be evaluated in the wrong memory states.
           Come back to this and figure it out.
         *)

        (*
        simpl.
        repeat norm_v.
        unfold eval_op.
        eutt_hide_rel; eutt_hide_left.

        unfold R'' in *.

        cbn* in HR''0.
        cbn*.
        clear -HR''0.
        symmetry in HR''0.
        repeat norm_v.
        unfold IntType.

        (* YZ TODO : [typ_to_dtyp] is just not manageable. Find a way to fix *)
        Axiom typ_to_dtyp_I : forall s i, typ_to_dtyp s (TYPE_I i) ≡ DTYPE_I i.
        rewrite typ_to_dtyp_I.
        match goal with
        |- eutt _ _ (ITree.bind _ ?t) => remember t end.
        unfold convert_typ, ConvertTyp_exp in HR''0.

        rewrite HR''0.
        rewrite HR''.
        {
          clear; intros.
          unfold typ_to_dtyp, typ_to_dtyp_func.
          cbn.



        unfold typ_to_dtyp at 3, typ_to_dtyp_func.

        rewrite HR''.
        exfalso.


        (* YZ TODO specialized tactic to use the same current value *)
        ret_bind_l_left (memH,MInt64asNT.NTypeDiv i2 i3).
        eutt_hide_rel; eutt_hide_left.

        (* TODO YZ : rename [eval_op] to [denote_op] *)
        simpl denote_exp.
        admit.
         *)


        (* unfold translate_E_vellvm_cfg in *. *)
        (* cbn in IHnexp1. *)
        (* rewrite interp_cfg_to_L3_bind in IHnexp1. *)
        (* rewrite translate_bind in IHnexp1. *)
        (* eapply eutt_clo_bind. *)
        admit.
 Admitted.

  (* Not yet clear whether this version is the useful one, but it's a consequence of the one above I think *)
  (* YZ TODO : investigate *)
  Lemma genNExpr_correct :
    forall (* Compiler bits *) (s1 s2: IRState)
      (* Helix  bits *)   (nexp: NExpr) (σ: evalContext) (memH: memoryH)
      (* Vellvm bits *)   (exp: exp typ) (c: code typ) (g : global_env) (l : local_env) (memV : memoryV),
      genNExpr nexp s1 ≡ inr (s2, (exp, c)) -> (* Compilation succeeds *)
      WF_IRState σ s1 ->                       (* Well-formed IRState *)
      R σ memH (memV, (l, g)) ->
      (* (WF_IRState σ s2 /\ *)
       eutt (lift_R_memory_cfg R σ ⩕ lift_R_result_cfg R' σ)
            (translate_E_helix_cfg
               (interp_Mem (denoteNExpr σ nexp)
                           memH))
            (translate_E_vellvm_cfg
               (interp_cfg_to_L3 helix_intrinsics
                                  (denote_code (convert_typ [] c) ;;
                                   translate exp_E_to_instr_E (denote_exp (Some (DTYPE_I 64%Z)) (convert_typ [] exp)))
                  g l memV)).
  Proof.
    intros s1 s2 nexp; revert s1 s2; induction nexp; intros * COMPILE WFIR PRE;
      assert (FOO: (s2,(exp,c)) ≡ (s2,(exp,c))) by reflexivity. (* TODOYZ: stupid hack to quickly check what case we are in. To remove *)
    - (* Variable case *)

      (* Reducing the compilation *)
      (* simp_comp COMPILE; (split; [auto |]). *)
      simp_comp COMPILE.

      + (* The variable maps to an integer in the IRState *)
        unfold denoteNExpr; cbn*.

        repeat norm_v.
        break_inner_match_goal.
        * (* Variable not in context, [context_lookup] fails *)
          abs_by WF_IRState_lookup_cannot_fail.
        * break_inner_match_goal.
          ++ repeat norm_h.
             destruct i0.
             { (* Global *)
               cbn*.
               repeat norm_v.
               cbn; repeat norm_v.
               2: eapply R_GLU; eauto.
               (** TODO: Define specialized version on eutt for external use *)
               apply eqit_Ret.
               split; [apply PRE | reflexivity].
             }
             { (* Local *)
               cbn*.
               repeat norm_v.
               2: eapply R_LLU; eauto.
               cbn; repeat norm_v.
               apply eqit_Ret.
               split; [apply PRE | reflexivity].
             }
          ++
            (** TODO YZ : get this automatically discharged by [abs_by] *)
            exfalso. eapply WF_IRState_lookup_int in WFIR; eauto.
            destruct WFIR as [? WFIR]; rewrite Heqs in WFIR; inv WFIR.
          ++
            exfalso. eapply WF_IRState_lookup_int in WFIR; eauto.
            destruct WFIR as [? WFIR]; rewrite Heqs in WFIR; inv WFIR.

      + (* The variable maps to a pointer *)

        abs_by WF_IRState_lookup_pointer.

    - (* Constant *)

      simp_comp COMPILE(* ; split; auto *).
      unfold denoteNExpr; cbn*.
      repeat norm_h.
      repeat norm_v.
      apply eqit_Ret.
      split; [apply PRE |].
      rewrite repr_intval; reflexivity.

    - (* NDiv *)

      simp_comp COMPILE.

      generalize Heqs; intros WFI; eapply WFevalNexp_succeed in WFI; eauto.

      eutt_hide_right.
      unfold denoteNExpr in *; cbn*.

      break_inner_match_goal; [| break_inner_match_goal].
      + clear - Heqs Heqs1 WFIR; abs_by WFevalNexp_no_fail.
      + clear - Heqs0 WFI Heqs2; abs_by WFevalNexp_no_fail.
      + repeat norm_h.

        (* TODO YZ: gets some super specialize tactics that do not require to provide variables *)
        specialize (IHnexp1 _ _ _ _ _ _ _ _ _ Heqs WFIR PRE).
        cbn* in IHnexp1.

        ret_bind_l_left i2.
        subst.
        eutt_hide_left.
        cbn*.
        repeat norm_v.
        rewrite convert_typ_app, denote_code_app.
        repeat norm_v.


        repeat norm_v.
        subst.

        (* unfold translate_E_vellvm_cfg in *. *)
        (* cbn in IHnexp1. *)
        (* rewrite interp_cfg_to_L3_bind in IHnexp1. *)
        (* rewrite translate_bind in IHnexp1. *)
        (* eapply eutt_clo_bind. *)
        admit.

  Admitted.

End NExpr.

Section MExpr.

  Definition R (σ : evalContext) (memH : memoryH) (vellvm : memoryV * (local_env * global_env)) : Type
    := memory_invariant σ memH vellvm.

  Definition R_MExpr
             (σ : evalContext)
             (helix : memoryH * mem_block)
             (vellvm : memoryV * (local_env * res_L1)) : Prop
    :=
      let '(memH, mb) := helix in
      let '(memV, (lenv, (genv, res))) := vellvm in
      memory_invariant σ memH (memV, (lenv, genv)) /\
      exists ptr,
        res ≡ UVALUE_Addr ptr.

  (* TODO: Do I need to explicitly relate mb and res above? *)
      (* exists ptr_llvm bk_llvm, *)
      (*   res ≡ UVALUE_Addr ptr_llvm /\ *)
      (*   get_logical_block (fst memV) ptr_llvm ≡ Some bk_llvm /\ *)
      (*   (* Memory matches value *) *)
      (*   (∀ (i : Int64.int) size, *)
      (*       Int64.lt i size *)
      (*       → ∃ (v_helix : binary64) (v_llvm : uvalue), *)
      (*         mem_lookup (MInt64asNT.to_nat i) mb ≡ Some v_helix *)
      (*         ∧ mem_lookup_llvm_at_i bk_llvm (MInt64asNT.to_nat i) (MInt64asNT.to_nat size) v_llvm *)
      (*         ∧ v_llvm ≡ UVALUE_Double v_helix). *)


  (** ** Compilation of MExpr TODO
  *)
  Lemma genMExpr_correct :
    forall (* Compiler bits *) (s1 s2: IRState)
      (* Helix  bits *)   (mexp: MExpr) (σ: evalContext) (memH: memoryH)
      (* Vellvm bits *)   (exp: exp typ) (c: code typ) (g : global_env) (l : local_env) (memV : memoryV) (τ: typ),
      genMExpr mexp s1 ≡ inr (s2, (exp, c, τ)) -> (* Compilation succeeds *)
      WF_IRState σ s1 ->                            (* Well-formed IRState *)
      R σ memH (memV, (l, g)) ->
      (* (WF_IRState σ s2 /\ *)
       eutt (R_MExpr σ)
            (translate_E_helix_cfg
               (interp_Mem (denoteMExpr σ mexp)
                           memH))
            (translate_E_vellvm_cfg
               ((interp_cfg_to_L3 helix_intrinsics
                                  (D.denote_code (convert_typ [] c) ;; translate exp_E_to_instr_E (D.denote_exp (Some (DTYPE_I 64%Z)) (convert_typ [] exp))))
                  g l memV)).
  Proof.
    intros s1 s2 mexp σ memH exp c g l memV τ Hgen Hwf Hmeminv.
    unfold denoteMExpr; cbn*.
    destruct mexp as [[vid] | mblock].
    - unfold denotePExpr; cbn*.

      (* Extracting information from genMExpr *)
      unfold genMExpr in Hgen.
      cbn in Hgen.
      destruct (nth_error (vars s1) vid) eqn:Hsnth.
      Focus 2. admit.
      cbn in Hgen. destruct p.
      destruct t; inversion Hgen.
      destruct t; inversion Hgen.
      destruct t; inversion Hgen.
      subst.

      unfold WF_IRState in Hwf.
      pose proof (Hwf _ _ _ Hsnth) as (v & Hnth & Hirtyp).

      rewrite Hnth.
      destruct v. inversion Hirtyp. inversion Hirtyp.
      clear Hirtyp. (* TODO: I know this is bogus, fix up. *)

      (* TODO: Clean this up. Extract into a lemma which spits out bk_helix? *)
      (* Need something relating σ and memH... memory_invariant should do this *)
      unfold R in Hmeminv.
      (* TODO: don't unfold this, separate into lemma. *)
      unfold memory_invariant in Hmeminv.
      destruct Hmeminv as [Hlength | (iota & Hmeminv)].

      { apply ListUtil.length_0 in Hlength; subst.
        rewrite nth_error_nil in Hnth.
        inversion Hnth. }

      pose proof Hmeminv as Hmeminv'.
      specialize (Hmeminv _ _ Hnth). cbn in Hmeminv.
      destruct Hmeminv as (bk_helix & Hlookup & ptr_llvm & bk_llvm & Hfind & rest).

      repeat norm_h;
        try (apply memory_lookup_err_inr_Some_eq; eauto).

      (* Try to simplify right hand side *)
      cbn.
      norm_v.

      (* TODO: Do I know anything about what i should be?
      memory_invariant seems to suggest that it can only be a local
      id. *)
      destruct i as [id | id].
      (* TODO: can probably avoid + *)
      + (* Global read *)
        (* It maybe should just be local? *)
        repeat (cbn; repeat norm_v).

        Focus 2.
        admit.
        admit.
      + (* Local read *)
        repeat (cbn; repeat norm_v).
        Focus 2.
        assert (alist_find AstLib.eq_dec_raw_id (Traversal.endo id) l ≡ Some (UVALUE_Addr ptr_llvm)).
        admit. (* This is probably the relation that we want in the memory_invariant? *)
        apply H.

      (* Final relation with R'0 *)
      apply eqit_Ret.
      unfold R_MExpr.

      unfold memory_invariant.
      split.
      right. exists iota. apply Hmeminv'.
      exists ptr_llvm. reflexivity.
    -
  Admitted.

End MExpr.

Section AExpr.

  (** ** Compilation of MExpr TODO
  *)
  Lemma genAExpr_correct : forall R R',
    forall (* Compiler bits *) (s1 s2: IRState)
      (* Helix  bits *)   (aexp: AExpr) (σ: evalContext) (memH: memoryH)
      (* Vellvm bits *)   (exp: exp typ) (c: code typ) (g : global_env) (l : local_env) (memV : memoryV) (τ: typ),
      genAExpr aexp s1 ≡ inr (s2, (exp, c)) -> (* Compilation succeeds *)
      WF_IRState σ s1 ->                            (* Well-formed IRState *)
      R σ memH (memV, (l, g)) ->
      (* (WF_IRState σ s2 /\ *)
       eutt R'
            (translate_E_helix_cfg
               (interp_Mem (denoteAExpr σ aexp)
                           memH))
            (translate_E_vellvm_cfg
               ((interp_cfg_to_L3 helix_intrinsics
                                  (D.denote_code (convert_typ [] c) ;; translate exp_E_to_instr_E (D.denote_exp (Some (DTYPE_I 64%Z)) (convert_typ [] exp))))
                  g l memV)).
  Proof.
  Admitted.

End AExpr.

Section MemCopy.
  (** ** Compilation of MemCopy TODO
      Unclear how to state this at the moment.
      What is on the Helix side? What do the arguments correspond to?
   *)

  Lemma genMemCopy_correct :
    forall (* Compiler bits *) (s1 s2: IRState)
      (* Helix  bits *)   (σ: evalContext)
      (* Vellvm bits *)   (o: Int64.int) (x y: ident) (nextblock bid: block_id) (bks : list (LLVMAst.block typ)),
      genMemCopy o x y nextblock s1 ≡ inr (s2, (bid, bks)) -> (* Compilation succeeds *)
      WF_IRState σ s1 ->                                      (* Well-formed IRState *)
      False.
      (* eutt R'
            (translate_E_helix_cfg
               (interp_Mem (denoteAexp σ aexp)
                           memH))
            (translate_E_vellvm_cfg
               ((interp_cfg_to_L3 helix_intrinsics
                                  (D.denote_code (convert_typ [] c) ;; translate exp_E_to_instr_E (D.denote_exp (Some (DTYPE_I 64%Z)) (convert_typ [] exp))))
                  g l memV)).
       *)
  Proof.
  Admitted.

End MemCopy.

Section FSHAssign.
  (** ** Compilation of FSHAssign TODO
      Unclear how to state this at the moment
      What is on the Helix side? What do the arguments correspond to?
   *)
  Lemma genFSHAssign_correct :
    forall (* Compiler bits *) (s1 s2: IRState)
      (* Helix  bits *)   (σ: evalContext)
      (* Vellvm bits *)   (i o: Int64.int) (x y: ident) (src dst: NExpr) (nextblock bid: block_id) (bks : list (LLVMAst.block typ)),
      genFSHAssign i o x y src dst nextblock s1 ≡ inr (s2, (bid, bks)) -> (* Compilation succeeds *)
      WF_IRState σ s1 ->                                      (* Well-formed IRState *)
      False.
      (* eutt R'
            (translate_E_helix_cfg
               (interp_Mem (denoteAexp σ aexp)
                           memH))
            (translate_E_vellvm_cfg
               ((interp_cfg_to_L3 helix_intrinsics
                                  (D.denote_code (convert_typ [] c) ;; translate exp_E_to_instr_E (D.denote_exp (Some (DTYPE_I 64%Z)) (convert_typ [] exp))))
                  g l memV)).
       *)
  Proof.
  Admitted.

End FSHAssign.

Section WhileLoop.
  (** ** Compilation of loops TODO
      Unclear how to state this at the moment
      What is on the Helix side? What do the arguments correspond to?
   *)

  Lemma genWhileLoop_correct :
    forall (* Compiler bits *) (s1 s2: IRState)
      (* Helix  bits *) (σ: evalContext)
      (* Vellvm bits *) (prefix: string) (from to: exp typ) (loopvar: raw_id) (loopcontblock: block_id)
                        (body_entry: block_id) (body_blocks: list (LLVMAst.block typ)) (init_code: (code typ))
                        (nextblock: block_id) (bid: block_id) (bks : list (LLVMAst.block typ)),
      genWhileLoop prefix from to loopvar loopcontblock body_entry body_blocks init_code nextblock s1 ≡ inr (s2, (bid, bks)) -> (* Compilation succeeds *)
      WF_IRState σ s1 ->                                      (* Well-formed IRState *)
      False.
      (* eutt R'
            (translate_E_helix_cfg
               (interp_Mem (denoteAexp σ aexp)
                           memH))
            (translate_E_vellvm_cfg
               ((interp_cfg_to_L3 helix_intrinsics
                                  (D.denote_code (convert_typ [] c) ;; translate exp_E_to_instr_E (D.denote_exp (Some (DTYPE_I 64%Z)) (convert_typ [] exp))))
                  g l memV)).
       *)
  Proof.
  Admitted.

End WhileLoop.

Section IMapBody.
  (** ** Compilation of IMapBody TODO
   *)

  Lemma genIMapBody_correct :
    forall (* Compiler bits *) (s1 s2: IRState)
      (* Helix  bits *) (σ: evalContext) (f: AExpr)
      (* Vellvm bits *) (n: Int64.int) (x y: ident) (loopvar: raw_id) (nextblock: block_id) (bid: block_id) (bks: list (LLVMAst.block typ)),
      genIMapBody n x y f loopvar nextblock s1 ≡ inr (s2, (bid, bks)) -> (* Compilation succeeds *)
      WF_IRState σ s1 ->                                      (* Well-formed IRState *)
      False.
      (* eutt R'
            (translate_E_helix_cfg
               (interp_Mem (denoteAexp σ aexp)
                           memH))
            (translate_E_vellvm_cfg
               ((interp_cfg_to_L3 helix_intrinsics
                                  (D.denote_code (convert_typ [] c) ;; translate exp_E_to_instr_E (D.denote_exp (Some (DTYPE_I 64%Z)) (convert_typ [] exp))))
                  g l memV)).
       *)
  Proof.
  Admitted.

End IMapBody.

Section BinOpBody.
  (** ** Compilation of IMapBody TODO
   *)

  Lemma genBinOpBody_correct :
    forall (* Compiler bits *) (s1 s2: IRState)
      (* Helix  bits *) (σ: evalContext) (f: AExpr)
      (* Vellvm bits *) (n: nat) (x y: ident) (loopvar: raw_id) (nextblock: block_id) (bid: block_id) (bks: list (LLVMAst.block typ)),
      genBinOpBody n x y f loopvar nextblock s1 ≡ inr (s2, (bid, bks)) -> (* Compilation succeeds *)
      WF_IRState σ s1 ->                                      (* Well-formed IRState *)
      False.
      (* eutt R'
            (translate_E_helix_cfg
               (interp_Mem (denoteAexp σ aexp)
                           memH))
            (translate_E_vellvm_cfg
               ((interp_cfg_to_L3 helix_intrinsics
                                  (D.denote_code (convert_typ [] c) ;; translate exp_E_to_instr_E (D.denote_exp (Some (DTYPE_I 64%Z)) (convert_typ [] exp))))
                  g l memV)).
       *)
  Proof.
  Admitted.

End BinOpBody.

Section MemMap2Body.
  (** ** Compilation of IMapBody TODO
   *)

  Lemma genMemMap2Body_correct :
    forall (* Compiler bits *) (s1 s2: IRState)
      (* Helix  bits *) (σ: evalContext) (f: AExpr)
      (* Vellvm bits *) (n: nat) (x x0 y: ident) (loopvar: raw_id) (nextblock: block_id) (bid: block_id) (bks: list (LLVMAst.block typ)),
      genMemMap2Body n x x0 y f loopvar nextblock s1 ≡ inr (s2, (bid, bks)) -> (* Compilation succeeds *)
      WF_IRState σ s1 ->                                      (* Well-formed IRState *)
      False.
      (* eutt R'
            (translate_E_helix_cfg
               (interp_Mem (denoteAexp σ aexp)
                           memH))
            (translate_E_vellvm_cfg
               ((interp_cfg_to_L3 helix_intrinsics
                                  (D.denote_code (convert_typ [] c) ;; translate exp_E_to_instr_E (D.denote_exp (Some (DTYPE_I 64%Z)) (convert_typ [] exp))))
                  g l memV)).
       *)
  Proof.
  Admitted.

End MemMap2Body.

Section MemInit.
  (** ** Compilation of IMapBody TODO
      Hmm this one even refuses to get admitted!
   *)

(*
  Lemma genMemInit_correct :
    forall (* Compiler bits *) (s1 s2: IRState)
      (* Helix  bits *) (σ: evalContext) (initial: binary64)
      (* Vellvm bits *) (size: Int64.int) (y: ident) (nextblock: block_id) (bid: block_id) (bks: list (LLVMAst.block typ)),
      genMemInit size y initial nextblock s1 ≡ inr (s2, (bid, bks)) -> (* Compilation succeeds *)
      WF_IRState σ s1 ->                                      (* Well-formed IRState *)
      False.
      (* eutt R'
            (translate_E_helix_cfg
               (interp_Mem (denoteAexp σ aexp)
                           memH))
            (translate_E_vellvm_cfg
               ((interp_cfg_to_L3 helix_intrinsics
                                  (D.denote_code (convert_typ [] c) ;; translate exp_E_to_instr_E (D.denote_exp (Some (DTYPE_I 64%Z)) (convert_typ [] exp))))
                  g l memV)).
       *)
  Proof.
  Admitted.
  *)

End MemInit.

Section Power.
  (** ** Compilation of IMapBody TODO
   *)

  Lemma genPower_correct :
    forall (* Compiler bits *) (s1 s2: IRState)
      (* Helix  bits *) (σ: evalContext) (src dst: NExpr) (n: NExpr) (f: AExpr)
      (* Vellvm bits *) (i o: Int64.int) (x y: ident) (initial: binary64) (nextblock: block_id) (bid: block_id) (bks: list (LLVMAst.block typ)),
      genPower i o x y src dst n f initial nextblock s1 ≡ inr (s2, (bid, bks)) -> (* Compilation succeeds *)
      WF_IRState σ s1 ->                                      (* Well-formed IRState *)
      False.
      (* eutt R'
            (translate_E_helix_cfg
               (interp_Mem (denoteAexp σ aexp)
                           memH))
            (translate_E_vellvm_cfg
               ((interp_cfg_to_L3 helix_intrinsics
                                  (D.denote_code (convert_typ [] c) ;; translate exp_E_to_instr_E (D.denote_exp (Some (DTYPE_I 64%Z)) (convert_typ [] exp))))
                  g l memV)).
       *)
  Proof.
  Admitted.

End Power.

(* TO MOVE *)
Global Instance ConvertTyp_list {A} `{Traversal.Fmap A}: ConvertTyp (fun T => list (A T)) :=
  fun env => Traversal.fmap (typ_to_dtyp env).

Variant Box (T: Type): Type := box (t: T).
(* Protects from "direct" pattern matching but not from context one *)
Ltac protect H := apply box in H.
Ltac hide_string_hyp' H :=
  match type of H with
  | context [String ?x ?y] =>
    let msg := fresh "msg" in
    let eqmsg := fresh "EQ_msg" in
    remember (String x y) as msg eqn:eqmsg; protect eqmsg
  end.

Ltac hide_strings' :=
  repeat (
      match goal with
      | h: Box _ |- _ => idtac
      | h: context [String ?x ?y] |- _ =>
        let msg := fresh "msg" in
        let eqmsg := fresh "EQ_msg" in
        remember (String x y) as msg eqn:eqmsg;
        protect eqmsg
      | |- context [String ?x ?y] =>
        let msg := fresh "msg" in
        let eqmsg := fresh "EQ_msg" in
        remember (String x y) as msg eqn:eqmsg;
        protect eqmsg
      end).

Ltac forget_strings :=
  repeat (
      match goal with
      | h: context [String ?x ?y] |- _ =>
        let msg := fresh "msg" in
        generalize (String x y) as msg
      | |- context [String ?x ?y] =>
        let msg := fresh "msg" in
        generalize (String x y) as msg
      end).


Section GenIR.

  (* YZ TODO : reducing denote_bks exposes iter. Should we simply make it opaque? *)
  Opaque denote_bks.
  Opaque resolve_PVar genFSHAssign.

  Lemma compile_FSHCOL_correct :
    forall (** Compiler bits *) (s1 s2: IRState)
      (** Helix bits    *) (op: DSHOperator) (σ : evalContext) (memH : memoryH)
      (** Vellvm bits   *) (nextblock bid_in : block_id) (bks : list (LLVMAst.block typ))
      (env : list (ident * typ))  (g : global_env) (ρ : local_env) (memV : memoryV),
      nextblock ≢ bid_in -> (* YZ: not sure about this yet *)
      bisim_partial σ (memH,tt) (memV, (ρ, (g, (inl bid_in)))) ->
      genIR op nextblock s1 ≡ inr (s2,(bid_in,bks)) ->
      eutt (bisim_partial σ)
           (translate_E_helix_cfg
              (interp_Mem (denoteDSHOperator σ op) memH))
           (translate_E_vellvm_cfg
              (interp_cfg_to_L3 helix_intrinsics
                                (D.denote_bks (convert_typ env bks) bid_in)
                                g ρ memV)).
  Proof.
    intros s1 s2 op; revert s1 s2; induction op; intros * NEXT BISIM GEN.
    - cbn in GEN.
      hide_strings'.
      simp_comp GEN.
      eutt_hide_right; cbn*; repeat norm_h; subst.
      cbn*; repeat norm_v.
      (* YZ TODO : add denote_bks theory to the automation *)
      rewrite denote_bks_nil.
      cbn*; repeat norm_v.
      apply eqit_Ret; auto.

    - (*
      Assign case.
       Need some reasoning about
       - resolve_PVar
       - genFSHAssign
       - D.denote_bks over singletons
       *)
      destruct src,dst,p.
      cbn* in GEN.
      hide_strings'.
      simp_comp GEN.

      admit.
  Admitted.

End GenIR.

Section LLVMGen.

  (** YZ TODO
      This is initialized over the empty memory. That is incorrect. Run it over the initialze memory, and add the top level statement about compile
     global_extern == false?
   *)
  Lemma LLVMGen_correct: forall R,
    forall (* Compiler bits *) (s1 s2: IRState)
      (* Helix bits *)    (i o: Int64.int) (globals: list (string*DSHType)) (globals_extern: bool) (fshcol: DSHOperator) (funname: string) (σ: evalContext)
      (* Vellvm bits *)   tle,
      LLVMGen i o globals false fshcol funname s1 ≡ inr (s2, tle) ->
      eutt (* (bisim_final σ) *) R
           (translate_E_helix_mcfg
                      (interp_Mem (denoteDSHOperator σ fshcol) memory_empty))
           (semantics_llvm tle).
  Proof.
    (* intros p data pll H. *)
    (*   unfold compile_w_main, compile in H. *)
    (*   destruct p as [i o name globals op]. *)
    (*   destruct (initIRGlobals data globals) as [? | [data' ginit]] eqn:EQGlob; [inv H |]. *)
    (*   simpl in H. *)
    (*   destruct (ErrorWithState.evalErrS (LLVMGen i o globals false op name) newState) eqn: EQEVALERR; [inv H | inv H]. *)
    (*   unfold semantics_llvm. *)
    (*   unfold semantics_llvm_mcfg. *)
    (*   unfold lift_sem_to_mcfg. *)
    (*   match goal with *)
    (*     |- context[match ?p with | _ => _ end] => destruct p eqn:EQ *)
    (*   end. { *)
    (*     unfold ErrorWithState.evalErrS in EQEVALERR. *)
    (*     destruct (LLVMGen i o globals false op name newState) eqn:EQGEN; inv EQEVALERR. *)
  Admitted.

End LLVMGen.

(**
   Initialization of the memory
 **)

Definition llvm_empty_memory_state_partial: LLVM_memory_state_cfg
  := (empty_memory_stack, ([], [])).

(* Scalar *)
Definition eval_const_double_exp (typed_expr:typ*exp typ): err dvalue :=
  match typed_expr with
  | (TYPE_Double, EXP_Double v) => ret (DVALUE_Double v)
  | (_, c_typ) => inl ("Type double expected: " ++ (to_string c_typ))%string
  end.

(* Array *)
Definition eval_const_arr_exp (typed_expr:typ*exp typ): err dvalue :=
  match typed_expr with
  | (TYPE_Array _ TYPE_Double, EXP_Array a) =>
    da <- ListSetoid.monadic_fold_left
           (fun ds d => dd <- eval_const_double_exp d ;; ret (dd::ds))
           [] a ;;
    ret (DVALUE_Array da)
  | (_, c_typ) => inl ("Array of doubles expected: " ++ (to_string c_typ))%string
  end.

Definition eval_const_exp (typed_expr:typ*exp typ): err dvalue :=
  match typed_expr with
  | (TYPE_Array _ TYPE_Double, EXP_Array a) => eval_const_arr_exp typed_expr
  | (TYPE_Double, EXP_Double v) =>  eval_const_double_exp typed_expr
  | (_, c_typ) => inl ("Unsupported constant expression type: " ++ (to_string c_typ))%string
  end.

(* TODO: move to Util *)
Definition assoc_right_to_left {A B C:Type}: (A*(B*C)) -> ((A*B)*C)
  := fun x => let '(a,(b,c)):=x in ((a,b),c).

(* TODO: move to Util *)
Definition assoc_left_to_right {A B C:Type}: ((A*B)*C) -> (A*(B*C))
  := fun x => let '((a,b),c) := x in (a,(b,c)).

(** Empty memories and environments should satisfy [memory_invariant] *)
Lemma memory_invariant_empty: memory_invariant [] helix_empty_memory llvm_empty_memory_state_partial.
Proof.
  unfold memory_invariant.
  break_let.
  left.
  auto.
Qed.

Fact initFSHGlobals_globals_sigma_len_eq
     {mem mem' data data'} globals σ:
  initFSHGlobals data mem globals ≡ inr (mem', data', σ) ->
  List.length globals ≡ List.length σ.
Proof.
  apply init_with_data_len.
Qed.

(* Maps indices from [σ] to [raw_id].
   Currently [σ := [globals;Y;X]]
   Where globals mapped by name, while [X-> Anon 0] and [Y->Anon 1]
*)
Definition memory_invariant_map (globals : list (string * DSHType)): nat -> raw_id
  := fun j =>
       let l := List.length globals in
       if Nat.eqb j l then Anon 0%Z (* X *)
       else if Nat.eqb j (S l) then Anon 1%Z (* Y *)
            else
              match nth_error globals j with
              | None => Anon 0%Z (* default value *)
              | Some (name,_) => Name name
              end.

Lemma memory_invariant_map_injectivity (globals : list (string * DSHType)):
  list_uniq fst globals ->
  forall (x y : nat),
    x < (Datatypes.length globals + 2)%nat ∧ y < (Datatypes.length globals + 2)%nat
    → memory_invariant_map globals x ≡ memory_invariant_map globals y → x ≡ y.
Proof.
  intros U x y [Hx Hy] E.
  unfold lt, peano_naturals.nat_lt in *.
  unfold memory_invariant_map in E.
  repeat break_if; repeat break_match; bool_to_nat; subst; try inv E; auto.
  - apply nth_error_None in Heqo; lia.
  - apply nth_error_None in Heqo; lia.
  -
    unfold list_uniq in U.
    eapply U; eauto.
  - apply nth_error_None in Heqo; lia.
Qed.

Fact initIRGlobals_cons_head_uniq:
  ∀ (a : string * DSHType) (globals : list (string * DSHType))
    (data : list binary64) (res : list binary64 * list (toplevel_entity typ (LLVMAst.block typ * list (LLVMAst.block typ)))),
    initIRGlobals data (a :: globals) ≡ inr res ->
    forall (j : nat) (n : string) (v : DSHType),
      (nth_error globals j ≡ Some (n, v) /\ n ≡ fst a) → False.
Proof.
  intros a globals data res H j n v C.
  unfold initIRGlobals, global_uniq_chk in H.
  cbn in H.
  repeat break_match_hyp; try inl_inr.
  unfold assert_false_to_err in Heqs.
  repeat break_match_hyp; try inl_inr.
  inl_inr_inv.
  subst.
  assert(globals_name_present (fst a) globals ≡ true).
  {
    clear -C.
    apply nth_to_globals_name_present.
    exists (n,v).
    exists j.
    apply C.
  }
  congruence.
Qed.

(* If [initIRGlobals] suceeds, the names of variables in [globals] were unique *)
Lemma initIRGlobals_names_unique {globals data res}:
  initIRGlobals data globals ≡ inr res → list_uniq fst globals.
Proof.
  revert res data.
  induction globals; intros.
  -
    cbn in H.
    inv H.
    apply list_uniq_nil.
  -
    apply list_uniq_cons.
    split.
    +
      cbn in H.
      break_match_hyp;[inl_inr|].
      break_match_hyp;[inl_inr|].
      break_let; subst.
      break_match_hyp;[inl_inr|].
      break_let; subst.
      inv H.
      eapply IHglobals.
      eauto.
    +
      (* [a] must not be present in [globals] *)
      unfold not.
      intros C.
      destruct C as (j & [n v] & C); cbn in C.
      eapply initIRGlobals_cons_head_uniq; eauto.
Qed.

(* Note: this could not be proben for arbitrary [chk] function,
   so we prove this only for [no_chk] *)
Lemma init_with_data_app
      {A: Type} (* input values *)
      {B: Type} (* output values we collect *)
      {C: Type} (* data *)
      (f: C -> A -> err (C*B))
      (c c': C) (* initial data *)
      (l0 l1: list A)
      (b: list B)
  :
    init_with_data f no_chk c (l0++l1) ≡ inr (c',b) ->
    ∃ c1 b1 b2,
      (init_with_data f no_chk c l0 ≡ inr (c1,b1) /\
       init_with_data f no_chk c1 l1 ≡ inr (c',b2) /\
       b ≡ (b1 ++ b2)%list).
Proof.
  revert l0 l1 c c' b.
  induction l0; intros.
  -
    cbn in H.
    repeat eexists.
    eauto.
  -
    cbn in H.
    repeat break_match_hyp; try inl_inr.
    inl_inr_inv.
    subst.
    apply IHl0 in Heqs0; clear IHl0.
    destruct Heqs0 as (c1 & b1 & b2 & H1 & H2 & E).
    repeat eexists; cbn.
    +
      rewrite Heqs.
      rewrite H1.
      eauto.
    +
      eauto.
    +
      cbn.
      f_equiv.
      auto.
Qed.

Lemma monadic_fold_left_err_app
         {A B : Type}
         (f : A -> B -> err A)
         (s0 s2 : A)
         (l0 l1 : list B):
  ListSetoid.monadic_fold_left f s0 (l0++l1) ≡ inr s2
  ->
  ∃ s1,
  ListSetoid.monadic_fold_left f s0 l0 ≡ inr s1 /\
  ListSetoid.monadic_fold_left f s1 l1 ≡ inr s2.
Proof.
  revert l0 l1 s0 s2 f.
  induction l0; intros.
  -
    cbn in *.
    eexists; auto.
  -
    cbn in H.
    break_match_hyp; [inl_inr|].
    eapply IHl0 in H.
    destruct H as [s1 [H1 H2]].
    eexists.
    split; [|eauto].
    cbn.
    rewrite Heqs.
    apply H1.
Qed.

(* TODO: This is general-purpose. Move elsewhere? *)
Lemma mapsto_alist_app_1st
      {K V: Type}
      (R : K → K → Prop)
      `{RD: RelDec.RelDec _ R}
      `{RDC: @RelDec.RelDec_Correct K R RD}
      (g g' : alist K V)
      (v : V)
      (n : K):
  mapsto_alist RD g n v ->
  mapsto_alist RD (g ++ g')%list n v.
Proof.
  revert v n.
  induction g; intros.
  -
    inversion H.
  -
    cbn.
    destruct a as [k0 v0].
    apply mapsto_alist_cons; [apply RDC|].
    destruct (RelDec.rel_dec n k0) eqn:K0.
    +
      right.
      split.
      *
        rewrite RelDec.rel_dec_correct in K0.
        apply K0.
      *
        apply mapsto_alist_cons in H ; [| auto].
        destruct H.
        destruct H.
        rewrite RelDec.rel_dec_correct in K0.
        congruence.
        apply H.
    +
      left.
      split.
      *
        apply IHg.
        apply mapsto_alist_cons in H ; [| auto].
        destruct H.
        apply H.
        destruct H.
        apply RelDec.rel_dec_correct in H.
        congruence.
      *
        apply RelDec.neg_rel_dec_correct in K0.
        apply K0.
Qed.

Lemma alist_find_nth_error_list_uniq
      (g : global_env)
      (x : nat)
      (n: raw_id)
      (v : dvalue)
      (U: list_uniq fst g):
  nth_error g x ≡ Some (n, v) →
  alist_find AstLib.eq_dec_raw_id n g ≡ Some v.
Proof.
  revert U.
  revert x v n.
  induction g; intros.
  -
    rewrite nth_error_nil in H.
    some_none.
  -
    cbn.
    break_let.
    break_if.
    +
      unfold RelDec.rel_dec, AstLib.eq_dec_raw_id in Heqb.
      cbn in Heqb.
      break_match; [| inversion Heqb].
      subst.
      destruct x.
      *
        cbn in H.
        some_inv.
        reflexivity.
      *
        cbn in H.
        clear - U H.
        exfalso.
        apply list_uniq_cons in U.
        destruct U.
        contradict H1.
        eexists.
        eexists.
        eauto.
    +
      destruct x.
      *
        clear IHg.
        cbn in *.
        some_inv.
        subst.
        clear - Heqb.
        unfold RelDec.rel_dec, AstLib.eq_dec_raw_id in Heqb.
        cbn in Heqb.
        break_if.
        inversion Heqb.
        contradict n0.
        reflexivity.
      *
        cbn in H.
        eapply IHg.
        eapply list_uniq_de_cons; eauto.
        eapply H.
Qed.


(** [memory_invariant] relation must holds after initialization of global variables *)
Lemma memory_invariant_after_init
      (p: FSHCOLProgram)
      (data: list binary64) :
  forall hmem σ hdata pll,
    helix_intial_memory p data ≡ inr (hmem,hdata,σ) /\
    compile_w_main p data ≡ inr pll ->
    eutt
      (memory_invariant_MCFG σ)
      (Ret (hmem, ()))
      (translate_E_vellvm_mcfg
         (interp_to_L3 helix_intrinsics
                       (build_global_environment (mcfg_of_tle pll))
                       [] ([],[]) ((Mem.empty, Mem.empty), [[]]))
      ).
Proof.
  intros hmem σ hdata pll [HI LI].

  (* unfold memory_invariant_MCFG, memory_invariant. *)
  unfold helix_intial_memory in *.
  cbn in HI.
  repeat break_match_hyp ; try inl_inr.
  subst.
  inv HI.
  cbn in LI.
  unfold ErrorWithState.evalErrS in LI.
  cbn in LI.

  eutt_hide_rel.
  repeat break_match_hyp; try inl_inr.
  inversion_clear LI.
  repeat inv_sum.
  repeat rewrite app_assoc.

  rewrite <- bind_ret_r. (* Add fake "bind" at LHS *)

  unfold build_global_environment.

  unfold allocate_globals.
  unfold map_monad_.
  simpl.

  rewrite 2!interp_to_L3_bind.
  rewrite bind_bind.
  unfold translate_E_vellvm_mcfg.
  rewrite translate_bind.
  rename Heqs into G, Heqs0 into L.
  rename e into eg.
  remember (eg ++
        [DSHPtrVal (S (Datatypes.length globals)) o;
        DSHPtrVal (Datatypes.length globals) i])%list as e.

  repeat rewrite ListUtil.flat_map_app.
  simpl.
  (* no more [genMain] *)
  clear Heqs5 Heqs3 i0 i1 l4 b.
  rename p3 into body_instr.
  rename m1 into mi, m0 into mo.
  apply eutt_clo_bind with (UU:=(lift_R_memory_mcfg memory_invariant_memory_mcfg) _ _ e).
  -
    (* allocate_global *)
    clear body_instr.
    induction globals.
    +
      cbn in G.
      inl_inr_inv.
      cbn in L.
      inl_inr_inv.
      subst.
      simpl.
      admit.
    +
      admit.
  -
    intros u1 u2 H.
    rewrite translate_bind.
    rewrite <- bind_ret_r. (* Add fake "bind" at LHS *)
    apply eutt_clo_bind with (UU:=(lift_R_memory_mcfg memory_invariant_memory_mcfg) _ _ e).
    +
      repeat break_let.
      rewrite interp_to_L3_ret.
      rewrite translate_ret.
      apply eutt_Ret.
      unfold lift_R_memory_mcfg in *.
      repeat break_let.
      apply H.
    +
      intros u0 u3 H0.
      repeat break_let.
      simpl.
      rewrite interp_to_L3_bind.
      rewrite translate_bind.
      rewrite <- bind_ret_r. (* Add fake "bind" at LHS *)
      apply eutt_clo_bind with (UU:=(lift_R_memory_mcfg memory_invariant_memory_mcfg) _ _ e).
      *
        cbn.
        rewrite interp_to_L3_bind.
        rewrite translate_bind.
        rewrite <- bind_ret_r. (* Add fake "bind" at LHS *)
        apply eutt_clo_bind with (UU:=(lift_R_memory_mcfg memory_invariant_memory_mcfg) _ _ e).
        --
          (* allocate_declaration *)
          admit.
        --
          intros u4 u5 H1.
          repeat break_let.
          rewrite interp_to_L3_ret.
          rewrite translate_ret.
          apply eutt_Ret.
          unfold lift_R_memory_mcfg in *.
          repeat break_let.
          auto.
      *
        intros u4 u5 H1.
        repeat break_let.
        unfold initialize_globals.
        unfold map_monad_.
        cbn.
        rewrite translate_bind.
        rewrite interp_to_L3_bind.
        rewrite translate_bind.
        rewrite <- bind_ret_r. (* Add fake "bind" at LHS *)
        apply eutt_clo_bind with (UU:=(lift_R_memory_mcfg memory_invariant_memory_mcfg) _ _ e).
        --
          (* initialize_global *)
          admit.
        --
          intros u7 u8 H2.
          repeat break_let.
          rewrite translate_ret.
          rewrite interp_to_L3_ret.
          rewrite translate_ret.
          apply eutt_Ret.
          unfold lift_R_memory_mcfg in *.
          repeat break_let.
          auto.
Admitted.


(* with init step  *)
Lemma compiler_correct_aux:
  forall (p:FSHCOLProgram)
    (data:list binary64)
    (pll: toplevel_entities typ (LLVMAst.block typ * list (LLVMAst.block typ))),
    compile_w_main p data ≡ inr pll ->
    eutt (bisim_full []) (semantics_FSHCOL p data) (semantics_llvm pll).
Proof.
Admitted.

(** Relation bewteen the final states of evaluation and execution
    of DHCOL program.

    At this stage we do not care about memory or environemnts, and
    just compare return value of [main] function in LLVM with
    evaulation results of DSHCOL.
 *)

Lemma bisim_partial_memory_subrelation: forall σ helix_state llvm_state,
    let '(mem_helix, _) := helix_state in
    let '(mem_llvm, (ρ, (g, _))) := llvm_state in
    bisim_partial σ helix_state llvm_state -> memory_invariant σ mem_helix (mem_llvm, (ρ, g)).
Proof.
  intros σ helix_state llvm_state.
  repeat break_let.
  subst.
  intros H.
  auto.
Qed.

(* Lemma bisim_full_partial_subrelation: forall σ helix_state llvm_state, *)
(*     let '(mem_helix, v_helix) := helix_state in *)
(*     let '(m, ((ρ,_), (g, v))) := llvm_state in *)
(*     bisim_full σ helix_state llvm_state -> bisim_partial σ (mem_helix, tt) (mk_LLVM_sub_state_partial_from_mem (inr v) (m, (ρ, g))). *)
(* Proof. *)
(*   intros σ helix_state llvm_state. *)
(*   repeat break_let. *)
(*   subst. *)
(*   intros H. *)
(*   unfold mk_LLVM_sub_state_partial_from_mem. *)
(*   auto. *)
(* Qed. *)

(* YZ TODO move  *)
From Vellvm Require Import AstLib.
  (* Top-level compiler correctness lemma  *)
  Theorem compiler_correct:
    forall (p:FSHCOLProgram)
      (data:list binary64)
      (pll: toplevel_entities typ (LLVMAst.block typ * list (LLVMAst.block typ))),
      compile_w_main p data ≡ inr pll ->
      eutt (bisim_final []) (semantics_FSHCOL p data) (semantics_llvm pll).
  Proof.
    intros p data pll H.
    unfold compile_w_main, compile in H.
    destruct p.
    cbn in *.
    break_match_hyp; try inv_sum.
    break_let; cbn in *.
    break_match_hyp; try inv_sum.
    unfold ErrorWithState.evalErrS in *.
    break_match_hyp; try inv_sum.
    break_match_hyp; cbn in *; repeat try inv_sum.
    break_let; cbn in *; inv_sum.
    repeat (break_match_hyp || break_let); try inv_sum.

    eutt_hide_left.
    repeat rewrite app_assoc.
    repeat rewrite <- app_assoc.
    match goal with
      |- context[_ :: ?x ++ ?y ++ ?z ++ ?t] => remember x as f1; remember y as f2; remember t as f3; remember z as f4
    end.

    unfold semantics_llvm.
    (* break_match_goal. *)
    (* mcfg_of_modul *)
    (* Lemma semantics_llvm_red : *)
    (*   forall p, semantics_llvm p ≈ semantics_llvm p. *)
    (* Proof. *)
    (*   unfold semantics_llvm. *)
    (*   intros p. *)
    (*   unfold lift_sem_to_mcfg. *)
    (*   break_match_goal. *)
    (*   { *)
    (*     unfold semantics_llvm_mcfg, model_to_L3, denote_vellvm_init, denote_vellvm, translate_E_vellvm_mcfg. *)
    (*     simpl bind. *)
    (*     rewrite interp_to_L3_bind, translate_bind. *)
    (*     match goal with *)
    (*     | ?t ≈ _ => assert (t ≈ ITree.bind (lift_sem_to_mcfg (fun p =>  *)


    (* setoid_rewrite bind_bind. *)
    (*   unfold translate_E_vellvm_mcfg. *)
    (* setoid_rewrite (interp_to_L3_bind helix_intrinsics . *)

    (* unfold lift_sem_to_mcfg. *)
    (* break_match_goal. *)
    (* { *)
    (*   unfold semantics_llvm_mcfg, model_to_L3, denote_vellvm_init, denote_vellvm. *)
    (*   simpl bind. *)
    (*   unfold translate_E_vellvm_mcfg. *)
    (*   rewrite interp_to_L3_bind, translate_bind. *)

    (*   rewrite modul_of_toplevel_entities *)
    (*           cons, !modul_of_toplevel_entities_app in Heqo0. *)


    (*   repeat match goal with *)
    (*          | h: mcfg_of_modul _ (_ @ _) ≡ _ |- _ => *)
    (*            apply mcfg_of_app_modul in h; *)
    (*              destruct h as (? & ? & ?EQ & ?EQ & <-) *)
    (*          end. *)
    (*   Transparent map_option. *)
    (*   cbn in EQ. *)
    (*   injection EQ; clear EQ; intro EQ. *)
    (*   subst. l0. f1 . *)
    (*   cbn in EQ0. *)


    (* } *)

    (* { *)
    (*   (* The conversion from top level entities to modul failed *) *)
    (*   (* There is a toplevel entity with an empty list of instruction *) *)
    (*   admit. *)
    (* } *)



    (*         unfold global_YX,constArray in EQ1. *)

Admitted.
