Require Import Helix.LLVMGen.Vellvm_Utils.
Require Import Helix.LLVMGen.Correctness_Prelude.
Require Import Helix.LLVMGen.EvalDenoteEquiv.
Require Import Helix.DynWin.DynWinProofs.
Require Import Helix.DynWin.DynWinTopLevel.
Require Import Helix.LLVMGen.Correctness_GenIR.
Require Import Helix.LLVMGen.Init.
Require Import Helix.LLVMGen.Correctness_Invariants.

Import ReifyRHCOL.
Import RHCOLtoFHCOL.
Import RSigmaHCOL.
Import RHCOL.
Import DynWin.
Import RHCOLtoFHCOL.
Import RHCOLEval.
Import FHCOLEval.
Import CarrierType.
Import SemNotations.
Import BidBound.
Import AlistNotations.

Lemma top_to_FHCOL :
  forall (a : Vector.t CarrierA 3) (* parameter *)
    (x : Vector.t CarrierA dynwin_i)  (* input *)
    (y : Vector.t CarrierA dynwin_o), (* output *)

      (* Evaluation of the source program.
         The program is fixed and hard-coded: the result is not generic,
         we provide a "framework". *)
      dynwin_orig a x = y →

      (* We cannot hide away the [R] level as we axiomatize the real to float
       approximation performed *)
      ∀ (dynwin_F_memory : memoryH)
        (dynwin_F_σ : evalContext)
        (dynwin_fhcol : FHCOL.DSHOperator),

        RHCOLtoFHCOL.translate DynWin_RHCOL = inr dynwin_fhcol →

        heq_memory () RF_CHE (dynwin_R_memory a x) dynwin_F_memory →
        heq_evalContext () RF_NHE RF_CHE dynwin_R_σ dynwin_F_σ ->

        ∀ a_rmem x_rmem : RHCOLEval.mem_block,
          RHCOLEval.memory_lookup (dynwin_R_memory a x) dynwin_a_addr = Some a_rmem →
          RHCOLEval.memory_lookup (dynwin_R_memory a x) dynwin_x_addr = Some x_rmem →

          DynWinInConstr a_rmem x_rmem →

          (* At the R-level, there are a memory and a memory block st... *)
          ∃ (r_omemory : RHCOLEval.memory) (y_rmem : RHCOLEval.mem_block),

            (* Evaluation succeeds and returns this memory *)
            RHCOLEval.evalDSHOperator dynwin_R_σ DynWin_RHCOL (dynwin_R_memory a x) (RHCOLEval.estimateFuel DynWin_RHCOL) = Some (inr r_omemory) ∧

            (* At the expected [y] address is found the memory block *)
              RHCOLEval.memory_lookup r_omemory dynwin_y_addr = Some y_rmem ∧


              MSigmaHCOL.MHCOL.ctvector_to_mem_block y = y_rmem ∧

              (* At the F-level, there are a memory and a memory block st... *)
              (∃ (f_omemory : memoryH) (y_fmem : mem_block),

                  (* Evaluation succeeds and returns this memory *)
                  evalDSHOperator dynwin_F_σ dynwin_fhcol dynwin_F_memory (estimateFuel dynwin_fhcol) = Some (inr f_omemory) ∧

                    (* At the expected [y] address is found the memory block *)
                    memory_lookup f_omemory dynwin_y_addr = Some y_fmem ∧

                    (* And this memory block is related to the R version *)
                    DynWinOutRel a_rmem x_rmem y_rmem y_fmem)
.
Proof.
  intros.
  eapply HCOL_to_FHCOL_Correctness; eauto.
Qed.

(* TODO *)
Section Program.

  Local Obligation Tactic := cbv;auto.
  Program Definition dynwin_i' : Int64.int := Int64.mkint (Z.of_nat dynwin_i) _.
  Program Definition dynwin_o' : Int64.int := Int64.mkint (Z.of_nat dynwin_o) _.
  Program Definition three : Int64.int := Int64.mkint 3 _.
  (* TODO pull and recompile?? *)
  (* TODO convert R global type signature to F global type signature? *)
  (* IZ : Construct the globals here *)
  Definition dynwin_globals' : list (string * FHCOL.DSHType)
    := cons ("a",DSHPtr three) nil.

  (* Here I should be able to compute the operator instead of quantifying over it in the statement *)
  Definition dynwin_fhcolp : FHCOL.DSHOperator -> FSHCOLProgram :=
    mkFSHCOLProgram dynwin_i' dynwin_o' "dyn_win" dynwin_globals'.

  (* Where do I build my data to pass to compile_w_main? *)
  (* Lookup in fmem yaddr xaddr and aaddr and flatten *)
  (* Definition dynwin_data (a_fmem x_fmem : FHCOLEval.mem_block): list binary64. *)
  (* Admitted. *)

End Program.

(* (* with init step  *) *)
(* Lemma compiler_correct_aux: *)
(*   forall (p:FSHCOLProgram) *)
(*     (data:list binary64) *)
(*     (pll: toplevel_entities typ (LLVMAst.block typ * list (LLVMAst.block typ))), *)
(*     forall s, compile_w_main p data newState ≡ inr (s,pll) -> *)
(*     eutt (succ_mcfg (bisim_full nil s)) (semantics_FSHCOL p data) (semantics_llvm pll). *)
(* Proof. *)
(*   intros * COMP. *)
(*   unshelve epose proof memory_invariant_after_init _ _ (conj _ COMP) as INIT_MEM. *)
(*   helix_initial_memory *)
(*   unfold compile_w_main,compile in COMP. *)
(*   cbn* in COMP. *)
(*   simp. *)
(*   unshelve epose proof @compile_FSHCOL_correct _ _ _ (* dynwin_F_σ dynwin_F_memory *) _ _ _ _ _ _ _ _ _ Heqs _ _ _ _. *)

Set Nested Proofs Allowed.
Import MonadNotation.
Local Open Scope monad_scope.
Import ListNotations.

(* Definition helix_initializer (p:FSHCOLProgram) (data:list binary64) *)
(*   : itree Event (nat*nat) := *)
(*   '(data, σ) <- denote_initFSHGlobals data p.(Data.globals) ;; *)
(*   xindex <- trigger (MemAlloc p.(i));; *)
(*   yindex <- trigger (MemAlloc p.(o));; *)
(*   let '(data, x) := constMemBlock (MInt64asNT.to_nat p.(i)) data in *)
(*   trigger (MemSet xindex x);; *)
(*   Ret (xindex,yindex). *)

Definition helix_finalizer (p:FSHCOLProgram) (yindex : nat)
  : itree Event _ :=
  bk <- trigger (MemLU "denote_FSHCOL" yindex);;
  lift_Derr (mem_to_list "Invalid output memory block" (MInt64asNT.to_nat p.(o)) bk).

(* Replacement for [denote_FSHCOL] where the memory is shallowy initialized using [helix_initial_memory].
   In this setup, the address at which [x] and [y] are allocated in memory is explicitly hard-coded rather than relying on the exact behavior of [Alloc].

 *)
Definition denote_FSHCOL' (p:FSHCOLProgram) (data:list binary64) σ
  : itree Event (list binary64) :=
  let xindex := List.length p.(globals) - 1 in
  let yindex := S xindex in
  let σ := List.app σ
                    [(DSHPtrVal yindex p.(o),false);
                     (DSHPtrVal xindex p.(i),false)]
  in
  denoteDSHOperator σ (p.(Data.op) : DSHOperator);;
  helix_finalizer p yindex.

Definition semantics_FSHCOL' (p: FSHCOLProgram) (data : list binary64) σ mem
  : failT (itree E_mcfg) (memoryH * list binary64) :=
  interp_helix (denote_FSHCOL' p data σ) mem.

(* TODO
   We want to express that the computed value is the right one
   Confused: compile with main returns the content of the [y] global.
   Is that the data or the address of the data in memory?
   The former makes little sense to me, but the latter even less as we are looking for a vector.
 *)
(* This is similar to [DynWinOutRel], see that for details.

   Looking at the definition of [DynWinOutRel],
   <<
    hopt_r (flip CType_impl)
      (RHCOLEval.mem_lookup dynwin_y_offset y_r)
      (FHCOLEval.mem_lookup dynwin_y_offset y_64).
   >>

   [FHCOLEval.mem_lookup dynwin_y_offset y_64]
   is the FHCOL output and needs to be proven equivalent to [llvm_out] here.

   [RHCOLEval.mem_lookup dynwin_y_offset y_r]
   is the RHCOL output and is already known to be equivalent to HCOL ([hcol_out] here).
 *)
Definition final_rel_val : Vector.t CarrierA dynwin_o -> uvalue -> Prop :=
  fun hcol_out llvm_out =>
    exists b64,
      llvm_out ≡ UVALUE_Array [UVALUE_Double b64]
      /\ CType_impl
          b64 (HCOLImpl.Scalarize hcol_out).

Definition final_rel : Rel_mcfg_OT (Vector.t CarrierA dynwin_o) uvalue :=
  succ_mcfg (fun '(_,vh) '(_,(_,(_,vv))) => final_rel_val vh vv).

Definition fhcol_to_llvm_rel_val : list binary64 -> uvalue -> Prop :=
  fun fhcol_out llvm_out =>
      llvm_out ≡ UVALUE_Array (List.map UVALUE_Double fhcol_out).

Definition fhcol_to_llvm_rel : Rel_mcfg_OT (list binary64) uvalue :=
  succ_mcfg (fun '(_,vh) '(_,(_,(_,vv))) => fhcol_to_llvm_rel_val vh vv).


Require Import LibHyps.LibHyps.

(* Lemma compiler_correct_aux: *)
(*   forall (p:FSHCOLProgram) *)
(*     (data:list binary64) *)
(*     (pll: toplevel_entities typ (LLVMAst.block typ * list (LLVMAst.block typ))), *)
(*   forall s hmem hdata σ, *)
(*     compile_w_main p data newState ≡ inr (s,pll) -> *)
(*     helix_initial_memory p data ≡ inr (hmem, hdata, σ) -> *)
(*     eutt fhcol_to_llvm_rel (semantics_FSHCOL' p data σ hmem) (semantics_llvm pll). *)
(* Proof. *)
(*   intros * COMP INIT. *)
(*   generalize COMP; intros COMP'. *)
(*   unfold compile_w_main,compile in COMP. *)
(*   cbn* in COMP. *)
(*   simp/g. *)
(*   epose proof @compile_FSHCOL_correct _ _ _ (* dynwin_F_σ dynwin_F_memory *) _ _ _ _ _ _ _ _ _ Heqs _ _ _ _. *)
(*   pose proof memory_invariant_after_init _ _ (conj INIT COMP') as INIT_MEM. *)
(*   match goal with *)
(*     |- context [semantics_llvm ?foo] => remember foo *)
(*   end. *)
(*   unfold semantics_llvm, semantics_llvm_mcfg, model_to_L3, denote_vellvm_init, denote_vellvm. *)
(*   simpl bind. *)
(*   rewrite interp3_bind. *)
(*   ret_bind_l_left ((hmem, tt)). *)
(*   eapply eutt_clo_bind. *)
(*   apply INIT_MEM. *)
(*   intros [? []] (? & ? & ? & []) INV. *)

(*   clear - Heqs1. *)

(*   unfold initIRGlobals,initIRGlobals_rev, init_with_data in Heqs1. *)

(*   rewrite interp3_bind. *)

(*   (* Need to get all the initialization stuff concrete I think? *) *)
(*   unfold initIRGlobals,initIRGlobals_rev, init_with_data in Heqs1. *)
(*   cbn in Heqs1. *)

(* Admitted. *)

(* Lemma compiler_correct_aux': *)
(*   forall (p:FSHCOLProgram) *)
(*     (data:list binary64) *)
(*     (pll: toplevel_entities typ (LLVMAst.block typ * list (LLVMAst.block typ))), *)
(*   forall s (* hmem hdata σ *), *)
(*     (* helix_initial_memory p data ≡ inr (hmem, hdata, σ) -> *) *)
(*     compile_w_main p data newState ≡ inr (s,pll) -> *)
(*     eutt fhcol_to_llvm_rel (semantics_FSHCOL p data) (semantics_llvm pll). *)
(* Proof. *)
(* Admitted. *)


(*
  STATIC: what are the arguments to compile_w_main
1. What is the data
(to_float (to_list y) ++ to_float (to_list x) ++ to_float (to_list a))
 and how do I build it? --> Would be some kind of propositional relation that IZ will write matching a quantifier against (to_list y ++ to_list x ++ to_list a) ?
2. How to build the globals to build the program?

3. Is helix_initial_memory p data === dynwin_F_memory ???
4. Same for dynwin_F_σ??
   dyn_F_σ


1. I know that I compile safely operators: gen_IR is correct, i.e. some initial invariant between mems on FHCOL and LLVM entails the right bisimilarity
2. What I'm intersted is compile_w_main: that creates two functions, a main and the operator. The main does some initialization.
   Ilia proved: the main that is produced by compiled with main is a LLVM computation that produces an LLVM memory that satisfies the right invariant AGAINST WHAT FHCOL memory? The one produced by helix_initial_memory

3. Use the fact that by top_to_FHCOL, the semantics of the operator is also the same as the source one, STARTING FROM dynwin_F_memory


run op a memory satisfying some predicate = some result = source result

run op helix_initial_memory = some result = if I run my llvm code

TODO: assume the hypotheses to instantiate top_to_FHCOL with helix_initial_memory
heq_memory () RF_CHE (dynwin_R_memory a x) mem →
heq_evalContext () RF_NHE RF_CHE dynwin_R_σ σ ->


helix_initial_memory _ data = (mem,_,σ) ->
heq_memory () RF_CHE (dynwin_R_memory a x) mem →
heq_evalContext () RF_NHE RF_CHE dynwin_R_σ σ ->

INITIAL MEMORY: what is the link between dynwin_F_memory and dynwin_F_sigma that are inherited from the top, with the result of helix_initial_memory = (hmem,hdata,σ): hmem == dynwin_F_memory and σ == dynwin_F_sigma?

 *)

Lemma helix_inital_memory_denote_initFSHGlobals :
  forall p data        (* FSHCOL static data  *)
    hmem hdata σ  (* FSHCOL dynamic data *),
    helix_initial_memory p data ≡ inr (hmem,hdata,σ) -> (* shallow memory initialization *)
    interp_helix (denote_initFSHGlobals data (globals p)) FHCOLITree.memory_empty ≈ (Ret (Some (hmem,(hdata,σ))) : itree E_mcfg _).
Admitted.

Definition heq_list : list CarrierA → list binary64 → Prop
  := Forall2 (RHCOLtoFHCOL.heq_CType' RF_CHE ()).

(* IZ TODO: This could be stated more cleanly, and proven equivalent *)
(* DynWinInConstr, only expressed on HCOL input directly *)
Definition input_inConstr
  (a : Vector.t CarrierA 3)
  (x : Vector.t CarrierA dynwin_i)
  : Prop :=
  DynWinInConstr
    (MSigmaHCOL.MHCOL.ctvector_to_mem_block a)
    (MSigmaHCOL.MHCOL.ctvector_to_mem_block x).

Lemma heq_list_nil : heq_list [] [].
Proof.
  constructor.
Qed.

Lemma heq_list_app : forall l1 l2 l,
    heq_list (l1 ++ l2) l ->
    exists l1' l2', l ≡ l1' ++ l2' /\ heq_list l1 l1' /\ heq_list l2 l2'.
Proof.
  induction l1; intros.
  - exists [], l; repeat split. apply heq_list_nil. apply H.
  - destruct l as [| a' l]; inv H.
    edestruct IHl1 as (l1' & l2' & ? & ? & ?); eauto.
    exists (a' :: l1'), l2'; repeat split; subst; eauto.
    constructor; auto.
Qed.

Lemma vector_to_list_length :
  forall A n (xs : Vector.t A n),
    Datatypes.length (Vector.to_list xs) ≡ n.
Proof.
  intros.
  induction n.
  - dep_destruct xs.
    reflexivity.
  - dep_destruct xs.
    specialize IHn with x.
    apply f_equal with (f := S) in IHn.
    rewrite <- IHn.
    reflexivity.
Qed.

Definition dynwin_F_σ :=
  [ (FHCOL.DSHPtrVal 0 three    , false) ;
    (FHCOL.DSHPtrVal 1 dynwin_o', false) ;
    (FHCOL.DSHPtrVal 2 dynwin_i', false) ].

Definition dynwin_F_memory a x :=
  memory_set
    (memory_set
      (memory_set
        memory_empty
          dynwin_a_addr (mem_block_of_list a))
      dynwin_y_addr mem_empty)
    dynwin_x_addr (mem_block_of_list x).


Lemma constList_app :
  forall n data rest data' data'' l1 l2,
    n <= Datatypes.length data ->
    constList n (data ++ rest) ≡ (data', l1) ->
    constList n data ≡ (data'', l2) ->
    l1 ≡ l2.
Proof.
  induction n; intros * Hn H1 H2.
  - cbn in *.
    inv H1; inv H2.
    reflexivity.
  - cbn in *.
    repeat break_let.
    repeat find_inversion.
    destruct data; [inv Heqp; inv Hn |].
    cbn in Hn.
    cbn in Heqp; inv Heqp.
    cbn in Heqp1; inv Heqp1.
    f_equal.
    apply le_S_n in Hn.
    destruct (constList n data) eqn:E.
    replace l0 with l3 in * by (eapply IHn; revgoals; eassumption).
    eapply IHn.
    + eassumption.
    + rewrite <- app_assoc in Heqp2.
      apply Heqp2.
    + eassumption.
Qed.

Lemma constList_firstn :
  forall n data data' l,
    constList n data ≡ (data', l) ->
    n <= Datatypes.length data ->
    l ≡ firstn n data.
Proof.
  induction n; intros * H Hn.
  - cbn in H.
    inv H.
    reflexivity.
  - cbn in H.
    do 2 break_let.
    find_inversion.
    destruct data; [inv Hn |].
    cbn in Heqp.
    inv Heqp.
    cbn.
    f_equal.
    cbn in Hn; apply le_S_n in Hn.
    destruct (constList n data) eqn:E.
    replace l0 with l2 in *
      by (eapply constList_app; revgoals; eassumption).
    eapply IHn; eassumption.
Qed.

Lemma rotateN_nil A n : @rotateN A n [] ≡ [].
Proof.
  induction n; auto.
  simpl; rewrite IHn; auto.
Qed.

Lemma rotateN_sing A n (x : A) : rotateN n [x] ≡ [x].
Proof.
  induction n; auto.
  simpl; rewrite IHn; auto.
Qed.

Lemma rotateN_cons A n (x : A) xs :
  rotateN (S n) (x :: xs) ≡ rotateN n (xs ++ [x]).
Proof.
  induction n; auto.
  simpl in *; rewrite IHn; auto.
Qed.

Lemma rotateN_firstn_reverse :
  forall A n (xs : list A),
    n <= Datatypes.length xs ->
    rotateN n xs ≡ skipn n xs ++ firstn n xs.
Proof.
  induction n; intros; [cbn; rewrite app_nil_r; auto |].
  destruct xs; [inv H |].
  cbn in H; apply le_S_n in H.
  cbn - [rotateN].
  unfold rotateN in *.
  rewrite nat_iter_S.
  rewrite IHn by (cbn; lia); clear IHn.
  destruct n; cbn; [rewrite app_nil_r; auto |].
  break_match; [destruct skipn; discriminate |].
  destruct (skipn n xs) eqn:E.
  + cbn in *. inv Heql. 
    assert (Datatypes.length (skipn n xs) ≡ 0) by (rewrite E; auto).
    pose proof skipn_length n xs.
    find_rewrite; lia.
  + cbn in Heql.
    inv Heql.
    replace (S n) with (1 + n) by auto.
    rewrite <- skipn_skipn, E, <- app_assoc; cbn.
    repeat f_equal.
    replace (S n) with (n + 1) by lia.
    rewrite MCList.firstn_add.
    rewrite E.
    reflexivity.
Qed.

(* MARK Vadim ? IZ TODO: generalize beyond just DynWin? *)
Lemma initial_memory_from_data :
  forall
    (a : Vector.t CarrierA 3)
    (x : Vector.t CarrierA dynwin_i)
    data,
    heq_list (Vector.to_list a ++ Vector.to_list x) data ->
    exists dynwin_F_memory data_garbage,
      helix_initial_memory (dynwin_fhcolp DynWin_FHCOL_hard) data
      ≡ inr (dynwin_F_memory, data_garbage, dynwin_F_σ)
      /\ RHCOLtoFHCOL.heq_memory () RF_CHE (dynwin_R_memory a x) dynwin_F_memory
      /\ RHCOLtoFHCOL.heq_evalContext () RF_NHE RF_CHE dynwin_R_σ dynwin_F_σ.
Proof.
  intros.
  unfold helix_initial_memory; cbn.
  repeat break_let; cbn.
  apply heq_list_app in H as (la & lx & Hdata & Hla & Hlx); subst.
  eexists (dynwin_F_memory la lx), _; break_and_goal.
  - repeat f_equal.
    unfold dynwin_F_memory.
    unfold dynwin_a_addr; cbn.
    unfold constMemBlock in *.
    repeat (break_let; find_inversion).
    enough (l3 ≡ la /\ l2 ≡ lx) as (? & ?) by (subst; reflexivity).
    apply Forall2_length in Hla, Hlx.
    rewrite vector_to_list_length in Hla, Hlx.
    copy_apply constList_firstn Heqp0; [| rewrite app_length; lia].
    rewrite firstn_app_exact in H by assumption; subst.
    apply constList_data in Heqp0; subst.
    rewrite rotateN_firstn_reverse in Heqp1 by (rewrite app_length; lia).
    rewrite skipn_app_exact, firstn_app_exact in Heqp1 by assumption.
    unfold dynwin_i in *.
    apply constList_firstn in Heqp1; [| rewrite app_length; lia].
    rewrite firstn_app_exact in Heqp1 by assumption.
    subst; split; auto.
  - clear - Hla Hlx.
    unfold heq_memory; intro.
    repeat (destruct k; [apply hopt_r_Some |]).
    + apply Forall2_length in Hla as Hla'.
      rewrite vector_to_list_length in Hla'.
      repeat (destruct la; try discriminate).
      clear - Hla.
      repeat dependent destruction a.
      unfold heq_list in Hla.
      repeat inv_prop Forall2.
      intro k.
      repeat (destruct k; [apply hopt_r_Some; assumption |]).
      apply hopt_r_None.
    + intro k.
      apply hopt_r_None.
    + apply Forall2_length in Hlx as Hlx'.
      rewrite vector_to_list_length in Hlx'.
      repeat (destruct lx; try discriminate).
      clear - Hlx.
      repeat dependent destruction x.
      unfold heq_list in Hlx.
      repeat inv_prop Forall2.
      intro k.
      repeat (destruct k; [apply hopt_r_Some; assumption |]).
      apply hopt_r_None.
    + apply hopt_r_None.
  - unfold heq_evalContext.
    repeat (apply Forall2_cons; [split; auto |]).
    4: apply Forall2_nil.
    all: apply heq_DSHPtrVal; reflexivity.
Qed.

Lemma interp_mem_interp_helix_ret_eq : forall E σ op hmem fmem v,
    interp_Mem (denoteDSHOperator σ op) hmem ≈ Ret (fmem,v) ->
    interp_helix (E := E) (denoteDSHOperator σ op) hmem ≈ Ret (Some (fmem,v)).
Proof.
  intros * HI.
  unfold interp_helix.
  rewrite HI.
  rewrite interp_fail_ret.
  cbn.
  rewrite translate_ret.
  reflexivity.
Qed.

Lemma option_rel_opt_r : forall {A} (R : A -> A -> Prop),
    HeterogeneousRelations.eq_rel (option_rel R) (RelUtil.opt_r R).
Proof.
  split; repeat intro.
  - cbv in H.
    repeat break_match; intuition.
    now constructor.
    now constructor.
  - inv H; now cbn.
Qed.

(* MARK *)
Lemma interp_mem_interp_helix_ret : forall E σ op hmem fmem,
    eutt equiv (interp_Mem (denoteDSHOperator σ op) hmem) (Ret (fmem,tt)) ->
    eutt equiv (interp_helix (E := E) (denoteDSHOperator σ op) hmem) (Ret (Some (fmem,tt))).
Proof.
  intros * HI.
  unfold interp_helix.
  assert (Transitive (eutt (E := E) (option_rel equiv))).
  - apply eutt_trans, option_rel_trans.
    intros x y z.
    unfold equiv, FHCOLtoSFHCOL.SFHCOLEval.evalNatClosure_Equiv.
    apply oprod_equiv_Equivalence.
  - unfold equiv, option_Equiv.
    rewrite <- option_rel_opt_r.
    unfold equiv, FHCOLtoSFHCOL.SFHCOLEval.evalNatClosure_Equiv in H.
Admitted.


(* Notation mcfg_ctx fundefs := *)
(*   (λ (T : Type) (call : CallE T), *)
(*     match call in (CallE T0) return (itree (CallE +' ExternalCallE +' IntrinsicE +' LLVMGEnvE +' (LLVMEnvE +' LLVMStackE) +' MemoryE +' PickE +' UBE +' DebugE +' FailureE) T0) with *)
(*     | LLVMEvents.Call dt0 fv args0 => *)
(*         dfv <- concretize_or_pick fv True;; *)
(*         match lookup_defn dfv fundefs with *)
(*         | Some f_den => f_den args0 *)
(*         | None => dargs <- map_monad (λ uv : uvalue, pickUnique uv) args0;; Functor.fmap dvalue_to_uvalue (trigger (ExternalCall dt0 fv dargs)) *)
(*         end *)
(*     end). *)

Import RecursionFacts.

Import TranslateFacts.

From Paco Require Import paco.
Import Interp.

#[local] Definition GFUNC dyn_addr b0 l4 main_addr :=
  [(DVALUE_Addr dyn_addr,
        ⟦ TFunctor_definition typ dtyp (typ_to_dtyp [])
            {|
              df_prototype :=
                {|
                  dc_name := Name "dyn_win";
                  dc_type :=
                    TYPE_Function TYPE_Void
                      [TYPE_Pointer (TYPE_Array (Npos 5) TYPE_Double);
                      TYPE_Pointer (TYPE_Array (Npos 1) TYPE_Double)];
                  dc_param_attrs := ([], [PARAMATTR_Readonly :: ArrayPtrParamAttrs; ArrayPtrParamAttrs]);
                  dc_linkage := None;
                  dc_visibility := None;
                  dc_dll_storage := None;
                  dc_cconv := None;
                  dc_attrs := [];
                  dc_section := None;
                  dc_align := None;
                  dc_gc := None
                |};
              df_args := [Name "X"; Name "Y"];
              df_instrs :=
                cfg_of_definition typ
                  {|
                    df_prototype :=
                      {|
                        dc_name := Name "dyn_win";
                        dc_type :=
                          TYPE_Function TYPE_Void
                            [TYPE_Pointer (TYPE_Array (Npos 5) TYPE_Double);
                            TYPE_Pointer (TYPE_Array (Npos 1) TYPE_Double)];
                        dc_param_attrs :=
                          ([], [PARAMATTR_Readonly :: ArrayPtrParamAttrs; ArrayPtrParamAttrs]);
                        dc_linkage := None;
                        dc_visibility := None;
                        dc_dll_storage := None;
                        dc_cconv := None;
                        dc_attrs := [];
                        dc_section := None;
                        dc_align := None;
                        dc_gc := None
                      |};
                    df_args := [Name "X"; Name "Y"];
                    df_instrs := (b0, l4)
                  |}
            |} ⟧f);
       (DVALUE_Addr main_addr,
       ⟦ TFunctor_definition typ dtyp (typ_to_dtyp [])
           {|
             df_prototype :=
               {|
                 dc_name := Name "main";
                 dc_type := TYPE_Function (TYPE_Array (Npos 1) TYPE_Double) [];
                 dc_param_attrs := ([], []);
                 dc_linkage := None;
                 dc_visibility := None;
                 dc_dll_storage := None;
                 dc_cconv := None;
                 dc_attrs := [];
                 dc_section := None;
                 dc_align := None;
                 dc_gc := None
               |};
             df_args := [];
             df_instrs :=
               cfg_of_definition typ
                 {|
                   df_prototype :=
                     {|
                       dc_name := Name "main";
                       dc_type := TYPE_Function (TYPE_Array (Npos 1) TYPE_Double) [];
                       dc_param_attrs := ([], []);
                       dc_linkage := None;
                       dc_visibility := None;
                       dc_dll_storage := None;
                       dc_cconv := None;
                       dc_attrs := [];
                       dc_section := None;
                       dc_align := None;
                       dc_gc := None
                     |};
                   df_args := [];
                   df_instrs :=
                     ({|
                        blk_id := Name "main_block";
                        blk_phis := [];
                        blk_code :=
                          [(IVoid 0%Z,
                           INSTR_Call (TYPE_Void, EXP_Ident (ID_Global (Name "dyn_win")))
                             [(TYPE_Pointer (TYPE_Array (Npos 5) TYPE_Double),
                              EXP_Ident (ID_Global (Anon 0%Z)));
                             (TYPE_Pointer (TYPE_Array (Npos 1) TYPE_Double),
                             EXP_Ident (ID_Global (Anon 1%Z)))]);
                          (IId (Name "z"),
                          INSTR_Load false (TYPE_Array (Npos 1) TYPE_Double)
                            (TYPE_Pointer (TYPE_Array (Npos 1) TYPE_Double),
                            EXP_Ident (ID_Global (Anon 1%Z))) None)];
                        blk_term :=
                          TERM_Ret (TYPE_Array (Npos 1) TYPE_Double, EXP_Ident (ID_Local (Name "z")));
                        blk_comments := None
                      |}, [])
                 |}
           |} ⟧f)].

#[local] Definition Γi :=
  {|
    block_count := 1;
    local_count := 2;
    void_count := 0;
    Γ :=
      [(ID_Global (Name "a"), TYPE_Pointer (TYPE_Array (Npos 3) TYPE_Double));
       (ID_Local (Name "Y1"), TYPE_Pointer (TYPE_Array (Npos 1) TYPE_Double));
       (ID_Local (Name "X0"), TYPE_Pointer (TYPE_Array (Npos 5) TYPE_Double))]
  |}.

#[local] Definition Γi' :=
  {|
    block_count := 1;
    local_count := 2;
    void_count := 0;
    Γ :=
      [(ID_Global (Name "a"), TYPE_Pointer (TYPE_Array (Npos 3) TYPE_Double));
       (ID_Global (Anon 1%Z), TYPE_Pointer (TYPE_Array (Npos 1) TYPE_Double));
       (ID_Global (Anon 0%Z), TYPE_Pointer (TYPE_Array (Npos 5) TYPE_Double))]
  |}.

Local Lemma Γi_bound : gamma_bound Γi.
Proof.
  unfold gamma_bound.
  intros.
  unfold LidBound.lid_bound.
  unfold VariableBinding.state_bound.
  apply nth_error_In in H.
  repeat invc_prop In; find_inversion.
  - exists "Y", {|
        block_count := 1;
        local_count := 1;
        void_count  := 0;
        Γ := [(ID_Global (Name "a"), TYPE_Pointer (TYPE_Array (Npos 3) TYPE_Double));
              (ID_Local (Name "X0"), TYPE_Pointer (TYPE_Array (Npos 5) TYPE_Double))]
      |}; eexists; break_and_goal.
    + reflexivity.
    + constructor.
    + reflexivity.
  - exists "X", {|
        block_count := 1;
        local_count := 0;
        void_count  := 0;
        Γ := [(ID_Global (Name "a"), TYPE_Pointer (TYPE_Array (Npos 3) TYPE_Double))]
      |}; eexists; break_and_goal.
    + reflexivity.
    + repeat constructor.
    + reflexivity.
Qed.

Local Lemma Γi'_bound : gamma_bound Γi'.
Proof.
  unfold gamma_bound.
  intros.
  unfold LidBound.lid_bound.
  unfold VariableBinding.state_bound.
  apply nth_error_In in H.
  repeat invc_prop In; find_inversion.
Qed.

#[local] Definition MCFG l6 l5 b0 l4 :=
  (TLE_Global {|
                               g_ident := Name "a";
                               g_typ := TYPE_Array (Npos 3) TYPE_Double;
                               g_constant := true;
                               g_exp := Some (EXP_Array l6);
                               g_linkage := Some LINKAGE_Internal;
                               g_visibility := None;
                               g_dll_storage := None;
                               g_thread_local := None;
                               g_unnamed_addr := true;
                               g_addrspace := None;
                               g_externally_initialized := false;
                               g_section := None;
                               g_align := Some 16%Z
                             |}
                           :: TLE_Global
                                {|
                                  g_ident := Anon 1%Z;
                                  g_typ := TYPE_Array (Npos 1) TYPE_Double;
                                  g_constant := true;
                                  g_exp := Some (EXP_Array [(TYPE_Double, EXP_Double MFloat64asCT.CTypeZero)]);
                                  g_linkage := None;
                                  g_visibility := None;
                                  g_dll_storage := None;
                                  g_thread_local := None;
                                  g_unnamed_addr := false;
                                  g_addrspace := None;
                                  g_externally_initialized := false;
                                  g_section := None;
                                  g_align := None
                                |}
                              :: TLE_Global
                                   {|
                                     g_ident := Anon 0%Z;
                                     g_typ := TYPE_Array (Npos 5) TYPE_Double;
                                     g_constant := true;
                                     g_exp := Some (EXP_Array l5);
                                     g_linkage := None;
                                     g_visibility := None;
                                     g_dll_storage := None;
                                     g_thread_local := None;
                                     g_unnamed_addr := false;
                                     g_addrspace := None;
                                     g_externally_initialized := false;
                                     g_section := None;
                                     g_align := None
                                   |}
                                 :: TLE_Comment "Prototypes for intrinsics we use"
                                    :: TLE_Declaration IntrinsicsDefinitions.fabs_32_decl
                                       :: TLE_Declaration IntrinsicsDefinitions.fabs_64_decl
                                          :: TLE_Declaration IntrinsicsDefinitions.maxnum_32_decl
                                             :: TLE_Declaration IntrinsicsDefinitions.maxnum_64_decl
                                                :: TLE_Declaration IntrinsicsDefinitions.minimum_32_decl
                                                   :: TLE_Declaration IntrinsicsDefinitions.minimum_64_decl
                                                      :: TLE_Declaration
                                                           IntrinsicsDefinitions.memcpy_8_decl
                                                         :: TLE_Comment "Top-level operator definition"
                                                            :: TLE_Definition
                                                                 {|
                                                                   df_prototype :=
                                                                     {|
                                                                       dc_name := Name "dyn_win";
                                                                       dc_type :=
                                                                         TYPE_Function TYPE_Void
                                                                           [TYPE_Pointer
                                                                              (TYPE_Array
                                                                              (Npos 5) TYPE_Double);
                                                                           TYPE_Pointer
                                                                             (TYPE_Array
                                                                              (Npos 1) TYPE_Double)];
                                                                       dc_param_attrs :=
                                                                         ([],
                                                                         [PARAMATTR_Readonly
                                                                          :: ArrayPtrParamAttrs;
                                                                         ArrayPtrParamAttrs]);
                                                                       dc_linkage := None;
                                                                       dc_visibility := None;
                                                                       dc_dll_storage := None;
                                                                       dc_cconv := None;
                                                                       dc_attrs := [];
                                                                       dc_section := None;
                                                                       dc_align := None;
                                                                       dc_gc := None
                                                                     |};
                                                                   df_args := [Name "X"; Name "Y"];
                                                                   df_instrs := (b0, l4)
                                                                 |}
                                                               :: genMain "dyn_win"
                                                                    (Anon 0%Z)
                                                                    (TYPE_Pointer
                                                                       (TYPE_Array (Npos 5) TYPE_Double))
                                                                    (Anon 1%Z)
                                                                    (TYPE_Array (Npos 1) TYPE_Double)
                                                                    (TYPE_Pointer
                                                                       (TYPE_Array (Npos 1) TYPE_Double))).

Definition MAIN :=
  {|
    df_prototype :=
      {|
        dc_name := Name "main";
        dc_type := TYPE_Function (TYPE_Array (Npos 1) TYPE_Double) [];
        dc_param_attrs := ([], []);
        dc_linkage := None;
        dc_visibility := None;
        dc_dll_storage := None;
        dc_cconv := None;
        dc_attrs := [];
        dc_section := None;
        dc_align := None;
        dc_gc := None
      |};
    df_args := [];
    df_instrs :=
      cfg_of_definition typ
                        {|
                          df_prototype :=
                            {|
                              dc_name := Name "main";
                              dc_type := TYPE_Function (TYPE_Array (Npos 1) TYPE_Double) [];
                              dc_param_attrs := ([], []);
                              dc_linkage := None;
                              dc_visibility := None;
                              dc_dll_storage := None;
                              dc_cconv := None;
                              dc_attrs := [];
                              dc_section := None;
                              dc_align := None;
                              dc_gc := None
                            |};
                          df_args := [];
                          df_instrs :=
                            ({|
                                blk_id := Name "main_block";
                                blk_phis := [];
                                blk_code :=
                                  [(IVoid 0%Z,
                                     INSTR_Call (TYPE_Void, EXP_Ident (ID_Global (Name "dyn_win")))
                                       [(TYPE_Pointer (TYPE_Array (Npos 5) TYPE_Double),
                                          EXP_Ident (ID_Global (Anon 0%Z)));
                                        (TYPE_Pointer (TYPE_Array (Npos 1) TYPE_Double),
                                          EXP_Ident (ID_Global (Anon 1%Z)))]);
                                   (IId (Name "z"),
                                     INSTR_Load false (TYPE_Array (Npos 1) TYPE_Double)
                                       (TYPE_Pointer (TYPE_Array (Npos 1) TYPE_Double),
                                         EXP_Ident (ID_Global (Anon 1%Z))) None)];
                                blk_term :=
                                  TERM_Ret (TYPE_Array (Npos 1) TYPE_Double, EXP_Ident (ID_Local (Name "z")));
                                blk_comments := None
                              |}, [])
                        |}
  |}.

Definition DYNWIN b0 l4 :=
{|
                        df_prototype :=
                          {|
                            dc_name := Name "dyn_win";
                            dc_type :=
                              TYPE_Function TYPE_Void
                                [TYPE_Pointer (TYPE_Array (Npos 5) TYPE_Double);
                                TYPE_Pointer (TYPE_Array (Npos 1) TYPE_Double)];
                            dc_param_attrs :=
                              ([], [PARAMATTR_Readonly :: ArrayPtrParamAttrs; ArrayPtrParamAttrs]);
                            dc_linkage := None;
                            dc_visibility := None;
                            dc_dll_storage := None;
                            dc_cconv := None;
                            dc_attrs := [];
                            dc_section := None;
                            dc_align := None;
                            dc_gc := None
                          |};
                        df_args := [Name "X"; Name "Y"];
                        df_instrs :=
                          cfg_of_definition typ
                            {|
                              df_prototype :=
                                {|
                                  dc_name := Name "dyn_win";
                                  dc_type :=
                                    TYPE_Function TYPE_Void
                                      [TYPE_Pointer (TYPE_Array (Npos 5) TYPE_Double);
                                      TYPE_Pointer (TYPE_Array (Npos 1) TYPE_Double)];
                                  dc_param_attrs :=
                                    ([], [PARAMATTR_Readonly :: ArrayPtrParamAttrs; ArrayPtrParamAttrs]);
                                  dc_linkage := None;
                                  dc_visibility := None;
                                  dc_dll_storage := None;
                                  dc_cconv := None;
                                  dc_attrs := [];
                                  dc_section := None;
                                  dc_align := None;
                                  dc_gc := None
                                |};
                              df_args := [Name "X"; Name "Y"];
                              df_instrs := (b0, l4)
                            |}
|}.

Definition MAINCFG := [{|
      blk_id := Name "main_block";
      blk_phis := [];
      blk_code :=
        [(IVoid 0%Z,
           INSTR_Call (typ_to_dtyp [] TYPE_Void, EXP_Ident (ID_Global (Name "dyn_win")))
             [(typ_to_dtyp [] (TYPE_Pointer (TYPE_Array (Npos 5) TYPE_Double)), EXP_Ident (ID_Global (Anon 0%Z))); (typ_to_dtyp [] (TYPE_Pointer (TYPE_Array (Npos 1) TYPE_Double)), EXP_Ident (ID_Global (Anon 1%Z)))]);
         (IId (Name "z"), INSTR_Load false (typ_to_dtyp [] (TYPE_Array (Npos 1) TYPE_Double)) (typ_to_dtyp [] (TYPE_Pointer (TYPE_Array (Npos 1) TYPE_Double)), EXP_Ident (ID_Global (Anon 1%Z))) None)];
      blk_term := TERM_Ret (typ_to_dtyp [] (TYPE_Array (Npos 1) TYPE_Double), EXP_Ident (ID_Local (Name "z")));
      blk_comments := None
    |}].

Require Import Helix.LLVMGen.Vellvm_Utils.
Definition mcfg_ctx := Vellvm_Utils.mcfg_ctx.
Opaque MCFG MAIN MAINCFG DYNWIN GFUNC mcfg_ctx.

Ltac hide_MCFG l6 l3 l5 b0 l4 :=
  match goal with
  | h : context[mcfg_of_tle ?x] |- _ =>
      progress change x with (MCFG l6 l3 l5 b0 l4) in h
  | |- context[semantics_llvm ?x] => progress change x with (MCFG l6 l3 l5 b0 l4)
  end.

Ltac hide_Γi :=
  match goal with
  | h : context [genIR _ _ ?x] |- _ => progress change x with Γi in h
  end.

Ltac hide_GFUNC dyn_addr b0 l4 main_addr :=
  match goal with
    |- context [denote_mcfg ?x] =>
      progress change x with (GFUNC dyn_addr b0 l4 main_addr)
  end.

Ltac hide_MAIN :=
  match goal with
    |- context [TFunctor_definition _ _ _ ?x] =>
      progress change x with MAIN
  end.

Ltac hide_DYNWIN b0 l4 :=
  match goal with
    |- context [TFunctor_definition _ _ _ ?x] =>
      progress change x with (DYNWIN b0 l4)
  end.

Ltac hide_mcfg_ctx dyn_addr b0 l4 main_addr :=
  match goal with
    |- context[interp_mrec ?x ] =>
      replace x with (mcfg_ctx (GFUNC dyn_addr b0 l4 main_addr)) by reflexivity
  end.

Ltac hide_MAINCFG :=
  match goal with
    |- context [[mk_block (Name "main_block") ?phi ?c ?t ?comm]] =>
      change [mk_block (Name "main_block") ?phi ?c ?t ?comm] with MAINCFG
  end.

Ltac HIDE l6 l3 l5 b0 l4 dyn_addr main_addr
  := repeat (hide_MCFG l6 l3 l5 b0 l4 || hide_GFUNC dyn_addr b0 l4 main_addr || hide_Γi || hide_MAIN || hide_DYNWIN b0 l4 || hide_mcfg_ctx dyn_addr b0 l4 main_addr || hide_MAINCFG).

Import ProofMode.

Set Printing Compact Contexts.

Local Lemma numeric_suffix_must_exist:
  forall ls rs n,
    CeresString.string_forall IdLemmas.is_alpha ls ->
    ls ≡ rs @@ string_of_nat n -> False.
Proof.
  intros ls rs n H C.
  rewrite C in H.
  apply IdLemmas.string_append_forall in H as [H1 H2].
  eapply IdLemmas.string_of_nat_not_empty.
  eapply IdLemmas.string_forall_contradiction.
  - eapply H2.
  - eapply IdLemmas.string_of_nat_not_alpha.
Qed.

Local Lemma dropLocalVars_Gamma_eq :
  forall s1 s1' s2 s2',
    dropLocalVars s1 ≡ inr (s1', ()) ->
    dropLocalVars s2 ≡ inr (s2', ()) ->
    Γ s1  ≡ Γ s2 ->
    Γ s1' ≡ Γ s2'.
Proof.
  intros.
  destruct s1; destruct s1'.
  destruct s2; destruct s2'.
  unfold dropLocalVars in *.
  simpl in *.
  unfold ErrorWithState.option2errS in *.
  repeat (break_if; try discriminate).
  repeat (break_match; try discriminate).
  unfold ret in *; simpl in *.
  repeat find_inversion.
  reflexivity.
Qed.

#[local]
Definition coe_Γi_Γi' (id : ident) : ident :=
  match id with
  | ID_Local "X0" => ID_Global (Anon 0%Z)
  | ID_Local "Y1" => ID_Global (Anon 1%Z)
  | _ => id
  end.

(*
  Γ only contains variables we care about [existing compile time].
  Others might exist at runtime, but Γ defines a subset of them.

  Γi' is the state after allocation, but before the operator is called.
  It has globals, but no local variables.
  Γi is the state during operator evalution: it does contain local variables.
*)
Local Lemma state_invariant_Γi :
  forall σ mem memI ρI ρI' gI a0 a1,
    (* global environment must contain addresses for input and output *)
    gI @ (Anon 0%Z) ≡ Some (DVALUE_Addr a0) ->
    gI @ (Anon 1%Z) ≡ Some (DVALUE_Addr a1) ->

    (* after we get inside the function, local environment will containan
       two new local vars with addresses for input and output *)
    ρI' @ (Name "X0") ≡ Some (UVALUE_Addr a0) ->
    ρI' @ (Name "Y1") ≡ Some (UVALUE_Addr a1) ->

    (* then the state invariant is preserved *)
    state_invariant σ Γi' mem (memI, (ρI , gI)) ->
    state_invariant σ Γi  mem (memI, (ρI', gI)).
Proof.
  intros * Hg0 Hg1 Hρ0 Hρ1 SINV.
  destruct SINV.
  constructor; try assumption.
  - unfold memory_invariant in *.
    intros.
    specialize mem_is_inv with n v b τ (coe_Γi_Γi' x).
    repeat (destruct n; try discriminate).
    all: inv H0.
    1: apply mem_is_inv; auto.
    all: conclude mem_is_inv assumption.
    all: conclude mem_is_inv auto.
    all: apply IRState_is_WF in H as [id H].
    all: destruct v; try (inv H; discriminate).
    all: destruct mem_is_inv as (ptr & τ & ? & ? & ? & ?).
    all: exists ptr, τ; break_and_goal; try assumption.
    all: cbn in H2.
    all: find_rewrite; find_inversion.
    all: cbn.
    all: assumption.
  - unfold WF_IRState, evalContext_typechecks in *.
    intros.
    specialize IRState_is_WF with v n b.
    apply IRState_is_WF in H.
    destruct H.
    repeat (destruct n; try discriminate).
    all: cbn in H.
    all: eexists.
    all: cbn.
    all: do 2 f_equal.
    all: inv H.
    all: destruct FHCOLITree.DSHType_of_DSHVal eqn:E in H2.
    all: try discriminate.
    all: try rewrite E.
    all: rewrite H2.
    all: reflexivity.
  - unfold no_id_aliasing.
    intros.
    all: repeat (destruct n1; try discriminate).
    all: repeat (destruct n2; try discriminate).
    all: try reflexivity.
    all: eapply st_no_id_aliasing; try eassumption.
    all: unshelve (inv H1; inv H2); assumption.
  - unfold no_llvm_ptr_aliasing_cfg, no_llvm_ptr_aliasing in *.
    intros.
    specialize st_no_llvm_ptr_aliasing with
      (coe_Γi_Γi' id1) ptrv1
      (coe_Γi_Γi' id2) ptrv2
      n1 n2 τ τ' v1 v2 b b'.
    all: repeat (destruct n1; try discriminate).
    all: repeat (destruct n2; try discriminate).
    all: inv H1; inv H2.
    all: try contradiction.
    all: apply st_no_llvm_ptr_aliasing; assumption || auto.
    all: try (intro; discriminate).
    all: cbn.
    all: cbn in H4, H5.
    all: repeat (find_rewrite; find_inversion).
    all: assumption.
  - apply Γi_bound.
Qed.


Lemma top_to_LLVM :
  forall (a : Vector.t CarrierA 3) (* parameter *)
    (x : Vector.t CarrierA dynwin_i) (* input *)
    (y : Vector.t CarrierA dynwin_o), (* y - output *)

      (* Evaluation of the source program.
         The program is fixed and hard-coded: the result is not generic,
         we provide a "framework". *)
      dynwin_orig a x = y →

      (* We cannot hide away the [R] level as we axiomatize the real to float
         approximation performed *)
      ∀
        (data : list binary64)
        (PRE : heq_list
                 (Vector.to_list a ++ Vector.to_list x)
                 data),

        (* the input data must be within bounds for numerical stability *)
        input_inConstr a x ->

        forall s pll
          (COMP : compile_w_main (dynwin_fhcolp DynWin_FHCOL_hard) data newState ≡ inr (s,pll)),
        exists g l m r, semantics_llvm pll ≈ Ret (m,(l,(g, r))) /\
                     final_rel_val y r.
Proof.
  intros/g.

  (* Specification of the initial memory on the helix side *)
  edestruct initial_memory_from_data
    as (dynwin_F_memory & data_garbage & HINIT & RFM & RFΣ);
    try eassumption/g.

  (* The current statement gives us essentially FHCOL-level inputs and outputs,
     and relate them to the source *)
  edestruct top_to_FHCOL
    with (dynwin_F_σ := dynwin_F_σ) (dynwin_F_memory := dynwin_F_memory)
    as (r_omemory & y_rmem' & EVR & LUR & TRR & f_omemory & y_fmem & EVF & LUF & TRF);
    eauto/g.

  instantiate (1:=DynWin_FHCOL_hard).
  rewrite DynWin_FHCOL_hard_OK.

  1,2,3: now repeat constructor.

  (* We know that we can see the evaluation of the FHCOL operator under an itree-lense  *)
  pose proof (Denote_Eval_Equiv _ _ _ _ _ EVF) as EQ.

  (* Breaking down the compilation process *)
  Opaque genIR.
  generalize COMP; intros COMP'.
  unfold compile_w_main,compile in COMP.
  simpl in COMP.
  simp.

  unfold initIRGlobals in Heqs0; cbn in Heqs0.
  break_let; cbn in Heqs0.
  inv_sum/g.

  unfold initXYplaceholders in Heqs3; cbn in Heqs3.
  break_let; cbn in Heqs3.
  inv_sum/g.

  unfold LLVMGen in Heqs1.
  Opaque genIR.
  cbn in Heqs1.
  break_match; [inv_sum |]/g. (* genIR DynWin_FHCOL_hard ("b" @@ "0" @@ "") Γi *)
  break_and; cbn in Heqs1/g.
  destruct s/g.
  break_match; [inv_sum |]/g.
  break_and; cbn in Heqs0 /g.
  inv_sum/g.
  cbn.

  (* Processing the construction of the LLVM global environment:
     We know that the two functions of interest have been allocated,
     and that the memories on each side satisfy the major relational
     invariant.
   *)
  pose proof memory_invariant_after_init _ _ (conj HINIT COMP') as INIT_MEM; clear COMP' HINIT.
  destruct u.

  (* The context gets... quite big. We try to prevent it as much as possible early on *)

  rename l0 into bks1, l4 into bks2.
  rename b0 into bk.
  rename l2 into exps1, l3 into exps3.
  rename i into s3, i0 into s2, i1 into s1.

  assert (HgenIR : genIR DynWin_FHCOL_hard "b0" Γi ≡ inr (s3, (b, bks1)))
    by apply Heqs; clear Heqs.
  rename Heqs2 into Hdrop.

  replace s3 with s2 in *; revgoals.
  { clear - Heqs0.
    unfold body_non_empty_cast in Heqs0.
    break_match; [destruct bks2; discriminate |].
    invc Heqs0; auto. }

  Tactic Notation "tmp" ident(exps3)
    ident(exps1)
    ident(exps2)
    ident(bk)
    ident(bks2)
    ident(dyn_addr)
    ident(main_addr)
    := HIDE exps3 exps1 exps2 bk bks2 dyn_addr main_addr.
  Ltac hide := tmp exps3 exps1 exps2 bk bks2 dyn_addr main_addr.
  hide.

  apply heq_list_app in PRE as (A & X & -> & EQA & EQX).

  (* match type of INIT_MEM with *)
  (* | context[mcfg_of_tle ?x] => remember x as tmp; cbn in Heqtmp; subst tmp *)
  (* end. *)

  (* match goal with *)
  (*   |- context [semantics_llvm ?x] => remember x as G eqn:VG; apply boxh_cfg in VG *)
  (* end. *)
  onAllHyps move_up_types.
  edestruct @eutt_ret_inv_strong as (RESLLVM & EQLLVMINIT & INVINIT); [apply INIT_MEM |].
  destruct RESLLVM as (memI & [ρI sI] & gI & []).
  inv INVINIT.
  destruct fun_decl_inv as [(main_addr & EQmain) (dyn_addr & EQdyn)].
  cbn in EQdyn.

  destruct anon_decl_inv as [(a0_addr & EQa0) (a1_addr & EQa1)].
  destruct genv_mem_wf_inv as [genv_ptr_uniq_inv genv_mem_bounded_inv].

  set (ρI' := (alist_add (Name "Y1") (UVALUE_Addr a1_addr)
              (alist_add (Name "X0") (UVALUE_Addr a0_addr) ρI))).

  eassert (state_inv' : state_invariant _ Γi _ (memI, (ρI', gI))).
  { eapply state_invariant_Γi with (ρI := ρI); eassumption || auto.
    eapply state_invariant_Γ'.
    - eassumption.
    - cbn.
      replace (Γ s1) with
        [(ID_Global "a", TYPE_Pointer (TYPE_Array (Npos 3) TYPE_Double))];
        [reflexivity |].
      erewrite dropLocalVars_Gamma_eq with (s1 := s2) (s2 := Γi); revgoals.
      + symmetry.
        eapply Context.genIR_Γ.
        eassumption.
      + cbn.
        reflexivity.
      + assumption.
      + reflexivity.
    - apply Γi'_bound. }

  (* We are getting closer to business: instantiating the lemma
     stating the correctness of the compilation of operators *)
  unshelve epose proof
    @compile_FSHCOL_correct _ _ _ dynwin_F_σ dynwin_F_memory _ _
                            (blk_id bk) _ gI ρI' memI HgenIR _ _ _ _
    as RES.
  - clear - EQ.
    unfold no_failure, has_post.
    apply eutt_EQ_REL_Reflexive_.
    intros * [H1 H2] H; subst.
    apply eutt_ret_inv_strong' in EQ as [[m ()] [EQ _]].
    rewrite interp_mem_interp_helix_ret_eq in H2.
    + apply Returns_Ret in H2; inv H2.
    + rewrite EQ; apply eutt_Ret; auto.
  - unfold bid_bound, VariableBinding.state_bound.
    exists "b",
      {| block_count := 0; local_count := 0; void_count := 0; Γ := Γ Γi |},
      {| block_count := 1; local_count := 0; void_count := 0; Γ := Γ Γi |}.
    cbn; auto.
  - apply state_inv'.
  - unfold Gamma_safe.
    intros id B NB.
    clear - B NB.
    dep_destruct NB.
    clear NB w e v.
    rename e0 into H0.
    destruct B as [name [s' [s'' [P [C1 [C2 B]]]]]].
    cbn in *.
    inv B.
    clear C1.
    cbn in *.
    repeat (destruct n; try discriminate).
    + cbn in H0.
      invc H0.
      replace "Y1" with ("Y" @@ string_of_nat 1) in H1 by auto.
      destruct name.
      { unfold append in H1 at 2.
        pose proof IdLemmas.string_of_nat_not_alpha (local_count s').
        rewrite <- H1 in H.
        apply IdLemmas.string_append_forall in H as [H _].
        cbn in H.
        discriminate. }
      destruct name.
      { invc H1.
        eapply string_of_nat_inj; [| eassumption].
        intro H.
        rewrite <- H in C2.
        invc C2.
        invc H1. }
      invc H1.
      fold append in H3.
      destruct name.
      { unfold append in H3.
        eapply IdLemmas.string_of_nat_not_empty.
        symmetry.
        eassumption. }
      invc H3.
    + cbn in H0.
      invc H0.
      replace "X0" with ("X" @@ string_of_nat 0) in H1 by auto.
      destruct name.
      { unfold append in H1 at 2.
        pose proof IdLemmas.string_of_nat_not_alpha (local_count s').
        rewrite <- H1 in H.
        apply IdLemmas.string_append_forall in H as [H _].
        cbn in H.
        discriminate. }
      destruct name.
      { invc H1.
        eapply string_of_nat_inj; [| eassumption].
        intro H.
        rewrite <- H in C2.
        invc C2. }
      invc H1.
      fold append in H3.
      destruct name.
      { unfold append in H3.
        eapply IdLemmas.string_of_nat_not_empty.
        symmetry.
        eassumption. }
      invc H3.
  - (* Assuming we can discharge all the preconditions,
       we prove here that it is sufficient for establishing
       our toplevel correctness statement.
     *)
    eapply interp_mem_interp_helix_ret in EQ.
    eapply eutt_ret_inv_strong' in EQ.
    destruct EQ as ([? |] & EQ & TMP); inv TMP.
    rewrite EQ in RES.
    clear EQ.
    destruct p as [? []].
    inv H3; cbn in H1; clear H2.
    edestruct @eutt_ret_inv_strong as (RESLLVM2 & EQLLVM2 & INV2); [apply RES | clear RES].
    destruct RESLLVM2 as (mem2 & ρ2 & g2 & v2).
    onAllHyps move_up_types.

    (* We need to reason about [semantics_llvm].
       Hopefully we now have all the pieces into our
       context, we try to go through it via some kind of
       symbolic execution to figure out what statement
       we need precisely.
     *)
    assert (forall x, semantics_llvm (MCFG exps3 exps1 bk bks2) ≈ x).
    { intros ?.

      unfold semantics_llvm, semantics_llvm_mcfg, model_to_L3, denote_vellvm_init, denote_vellvm.


      simpl bind.
      rewrite interp3_bind.
      (* We know that building the global environment is pure,
         and satisfy a certain spec.
       *)
      rewrite EQLLVMINIT.
      rewrite bind_ret_l.

      rewrite interp3_bind.
      focus_single_step_l.

      (* We build the open denotations of the functions, i.e.
         of "main" and "dyn_win".
        [memory_invariant_after_init] has guaranteed us that
        they are allocated in memory (via [EQdyn] and [EQmain])
       *)
      (* Hmm, amusing hack, [unfold] respects Opaque but not [unfold at i] *)
      unfold MCFG at 1 2; cbn.
      hide.

      rewrite !interp3_bind.
      rewrite !bind_bind.
      rewrite interp3_GR; [| apply EQdyn].

      rewrite bind_ret_l.
      rewrite interp3_ret.
      rewrite bind_ret_l.
      rewrite !interp3_bind.
      rewrite !bind_bind.
      rewrite interp3_GR; [| apply EQmain].
      repeat (rewrite bind_ret_l || rewrite interp3_ret).
      subst.
      cbn.
      rewrite interp3_bind.
      hide.

      (* We now specifically get the pointer to the main as the entry point *)
      rewrite interp3_GR; [| apply EQmain].
      repeat (rewrite bind_ret_l || rewrite interp3_ret).
      cbn/g.

      (* We are done with the initialization of the runtime, we can
         now begin the evaluation of the program per se. *)

      (* We hence first do a one step unfolding of the mutually
         recursive fixpoint in order to jump into the body of the main.
       *)
      rewrite denote_mcfg_unfold_in; cycle -1.
      {
        unfold GFUNC at 1.
        unfold lookup_defn.
        rewrite assoc_tl.
        apply assoc_hd.
        (* Need to keep track of the fact that [main_addr] and [dyn_addr]
           are distinct. Might be hidden somewhere in the context.
         *)
        clear - genv_ptr_uniq_inv EQmain EQdyn.
        intro H; inv H.
        enough (Name "main" ≡ Name "dyn_win") by discriminate.
        eapply genv_ptr_uniq_inv; eassumption || auto.
      }

      cbn.
      rewrite bind_ret_l.
      rewrite interp_mrec_bind.
      rewrite interp_mrec_trigger.
      cbn.
      rewrite interp3_bind.

      (* Function call, we first create a new memory frame *)
      rewrite interp3_MemPush.
      rewrite bind_ret_l.
      rewrite interp_mrec_bind.
      rewrite interp_mrec_trigger.
      cbn.
      rewrite interp3_bind.
      rewrite interp3_StackPush.

      rewrite bind_ret_l.
      rewrite interp_mrec_bind.
      rewrite interp3_bind.
      rewrite translate_bind.
      rewrite interp_mrec_bind.
      rewrite interp3_bind.
      rewrite bind_bind.
      cbn.

      hide.
      onAllHyps move_up_types.

      (* TODO FIX surface syntax *)
      (* TODO : should really wrap the either monad when jumping from blocks into a named abstraction to lighten goals
         TODO : can we somehow avoid the continuations being systematically
         MARK
         let (m',p) := r in
         let (l',p0) := p in
         let (g',_)  := p0 in ...
       *)
      (* MARK *)
      Notation "'lets' a b c d e f 'be' x y z 'in' x " :=
        (let (a,b) := x in
         let (c,d) := y in
         let (e,f) := z in
         x)
          (only printing, at level 10,
            format "'lets' a b c d e f 'be' x y z 'in' '//' x").


      (* We are now evaluating the main.
         We hence first need to need to jump into the right block
       *)
      rewrite denote_ocfg_unfold_in; cycle -1.
      unfold MAINCFG at 1; rewrite find_block_eq; reflexivity.

      rewrite typ_to_dtyp_void.
      rewrite denote_block_unfold.
      (* No phi node in this block *)
      rewrite denote_no_phis.
      rewrite bind_ret_l.
      rewrite bind_bind.

      (* We hence evaluate the code: it starts with a function call to "dyn_win"! *)

      rewrite denote_code_cons.
      rewrite bind_bind,translate_bind.
      rewrite interp_mrec_bind, interp3_bind.
      rewrite bind_bind.
      cbn.
      focus_single_step_l.

      hide.
      rewrite interp3_call_void; cycle 1.
      reflexivity.
      eauto.
      {
        unfold GFUNC at 1.
        unfold lookup_defn.
        apply assoc_hd.
      }
      hide.
      cbn.
      rewrite bind_bind.
      hide.
      rewrite translate_bind, interp_mrec_bind,interp3_bind, bind_bind.
      focus_single_step_l.

      (* This function call has arguments: we need to evaluate those.
         These arguments are globals that have been allocated during
         the initialization phase, but I'm afraid we lost this fact
         at this moment.
         In particular right now, we need to lookup in the global
         environment the address to an array stored at [Anon 0].

         Do I need to reinforce [memory_invariant_after_init] or is
         what I need a consequence of [genIR_post]?

         MARK
       *)

      Import AlistNotations.
      rewrite denote_mcfg_ID_Global; cycle 1.
      eassumption.

      rewrite bind_ret_l.
      subst.
      cbn.
      focus_single_step_l.

      match goal with
        |- context [interp_mrec ?x] => remember x as ctx
      end.
      rewrite !translate_bind, !interp_mrec_bind,!interp3_bind, !bind_bind.
      rewrite denote_mcfg_ID_Global; cycle 1.
      eassumption.
      rewrite !bind_ret_l, translate_ret, interp_mrec_ret, interp3_ret, bind_ret_l.
      rewrite translate_ret, interp_mrec_ret, interp3_ret, bind_ret_l.

      subst; rewrite !bind_bind; cbn; focus_single_step_l; unfold DYNWIN at 1; cbn; rewrite bind_ret_l.
      cbn; rewrite interp_mrec_bind, interp_mrec_trigger, interp3_bind.

      onAllHyps move_up_types.

      (* Function call, we first create a new memory frame *)
      rewrite interp3_MemPush, bind_ret_l, interp_mrec_bind, interp_mrec_trigger.
      cbn; rewrite interp3_bind, interp3_StackPush, bind_ret_l.
      rewrite !translate_bind,!interp_mrec_bind,!interp3_bind, !bind_bind.
      subst; focus_single_step_l.

      Notation "'ℑfunc' t" := (ℑs3 (interp_mrec (mcfg_ctx (GFUNC _ _ _ _)) t)) (at level 0, only printing).


      unfold DYNWIN at 2 3; cbn.

      unfold init_of_definition.
      cbn.

      unfold DYNWIN at 1.
      cbn[df_instrs blks cfg_of_definition fst snd].

      match type of Heqs0 with
      | body_non_empty_cast ?x ?s1 ≡ inr (?s2, (?bk, ?bks)) => assert (EQbks: bk :: bks2 ≡ x /\ s1 ≡ s2)
      end.
      {
        clear - Heqs0.
        destruct bks1; cbn in *; inv Heqs0; intuition.
      }
      clear Heqs0.
      destruct EQbks as [EQbks _].
      rewrite EQbks.
      unfold TFunctor_list'; rewrite map_app.
      rewrite denote_ocfg_app; [| apply list_disjoint_nil_l].
      rewrite translate_bind,interp_mrec_bind.
      rewrite interp3_bind, bind_bind.
      subst; focus_single_step_l.
      clear - EQLLVM2.

      replace (map (tfmap (typ_to_dtyp nil)) bks1) with (convert_typ nil bks1) by reflexivity.
      onAllHyps move_up_types.
      (* Set Printing All. *)


(* Lemma interp_mrec_comp : Prop. *)
(* refine (forall D1 D2 E *)
(*                            (ctx1 : D1 ~> itree ((D1 +' D2) +' E)) *)
(*                            (ctx2 : D2 ~> itree ((D1 +' D2) +' E)) *)
(*                            R (t : itree ((D1 +' D2) +' E) R), _:Prop). *)
(* refine (_ ≅ _). *)
(* refine (interp_mrec ctx *)
(*     interp_mrec ctx1 (interp_mrec ctx2 t) ≅ interp_mrec ctx1 (interp_mrec ctx2 t). *)

Notation tree := (itree _ _).

Ltac eqitree_of_eq h :=
  match type of h with
  | ?t ≡ ?u =>
      let name := fresh in
      assert (name: t ≅ u) by (subst; reflexivity); clear h; rename name into h
  end.
Tactic Notation "eqi_of_eq" ident(h) := eqitree_of_eq h.

#[global] Instance eq_itree_interp_cfg3:
  forall {T : Type}, Proper (eq_itree eq ==> eq ==> eq ==> eq ==> eq_itree eq) (@ℑ3 T).
Proof.
Admitted.

(* Global Instance eqitree_cong_eq {E R1 R2 RR}: *)
(*   Proper (eq_itree eq ==> eq_itree eq ==> flip impl) *)
(*          (@eq_itree E R1 R2 RR). *)
(* Proof. *)
(* Admitted. *)

Lemma interp_cfg3_to_mcfg3 :
  forall R a b c d (ctx : _ ~> itree (_ +' L0)) (t : itree instr_E _) g l s m,
    interp_cfg3  (R := R) t g l m                                                ≈ Ret3 a b c d ->
    interp_mcfg3 (R := R) (interp_mrec ctx (translate instr_to_L0' t)) g (l,s) m ≈ Ret3 a (b,s) c d .
Proof.
  intros *.
  revert g l m t.
  einit.
  ecofix IH.
  intros * EQ.
  onAllHyps move_up_types.
  punfold EQ.

  match type of EQ with
  | eqit_ _ _ _ _ _ ?t ?u => remember t as T
                            (* ; remember u as U *)
  end.

  eqi_of_eq HeqT.
  (* eqi_of_eq HeqU. *)
  revert t HeqT.
  red in EQ.
  dependent induction EQ.
  - intros.
    rewrite itree_eta, <- x in HeqT.
    clear T x.
    rewrite (itree_eta t) in HeqT.

  (* dependent induction EQ. *)
  (* - rewrite translate_ret, interp_mrec_ret, interp3_ret. *)
  (*   rewrite interp_cfg3_ret in EQ. *)
  (*   apply eutt_inv_Ret in EQ. *)
  (*   inversion EQ; subst. *)
  (*   reflexivity. *)
  (* - rewrite translate_tau, interp_mrec_tau, interp3_tau. *)

(*

  revert Heqou t Heqot.
  induction EQ.
  - intros .
    cbn in *.
    Ltac eqitree_of_eq h :=
      match type of h with
      | ?t ≡ ?u => assert (t ≅ u) by (subst; reflexivity); clear h
      end.
    eqitree_of_eq Heqot.
    eqitree_of_eq Heqot


  dependent induction EQ.
  - rewrite (itree_eta t). <- x.
    rewrite (itree_eta t) in EQ.
    destruct (observe t) eqn:EQt.
  - rewrite translate_ret, interp_mrec_ret, interp3_ret.
    rewrite interp_cfg3_ret in EQ.
    apply eutt_inv_Ret in EQ.
    inversion EQ; subst.
    reflexivity.
  - rewrite translate_tau, interp_mrec_tau, interp3_tau.

          rewrite interp_cfg3_ret in EQ.
          apply eutt_inv_Ret in EQ.
          inversion EQ; subst.
          reflexivity.


       refine (forall R (ctx : _ ~> itree (_ +' L0)) (t : itree instr_E _) g l m,
                 interp_mcfg3 (R := R) (interp_mrec ctx (translate instr_to_L0' t)) g l m ≈ _).
      refine (_ (interp_cfg3 (R := R) t g (fst l) m)).
      intros TRE.
      refine (interp_mrec ctx _).
        interp_mcfg3 (interp_mrec ctx t) g l m).


      match goal with
        h: eutt _ (interp_cfg3 (denote_ocfg ?t ?x) _ _ _ ) _ |-
          context [interp_mcfg3 (interp_mrec _ (translate _ (denote_ocfg ?u ?y))) _ _]
        => idtac x; idtac y
      end.
      Unset Printing Notations.

      eutt R t (interp_cfg3 u g ρ m) ->


      assert (
          ℑs3 (interp_mrec (mcfg_ctx



      Unset Printing Notations.


      destruct bks1 as [| bks1hd bks1].
      cbn in Heqs1.

      (* Shouldn't we be facing EQLLVM2 right now? *)
      (* rewrite denote_ocfg_unfold_in; cycle -1. *)
      (* apply find_block_eq; reflexivity. *)
      (* cbn. *)
      (* rewrite denote_block_unfold. *)

      (* Who's b0? *)
      (* Ah ok: we have extended the operator's cfg with a return block to terminate, and our [genIR_post]
         tells us we are about to jump to this ret block, so we need a lemma to piece this together *)


 *)

Admitted.