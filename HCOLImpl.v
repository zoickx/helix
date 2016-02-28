(* Low-level functions implementing HCOL matrix and vector manupulation operators *)

Require Import Spiral.
Require Import Rtheta.
Require Import SVector.

Require Import Arith.
Require Import Program. (* compose *)
Require Import Morphisms.
Require Import RelationClasses.
Require Import Relations.

Require Import CpdtTactics.
Require Import JRWTactics.
Require Import CaseNaming.

(* CoRN MathClasses *)
Require Import MathClasses.interfaces.abstract_algebra.
Require Import MathClasses.orders.minmax MathClasses.interfaces.orders.
Require Import MathClasses.theory.rings.
Require Import MathClasses.theory.naturals.

(*  CoLoR *)
Require Import CoLoR.Util.Vector.VecUtil.
Import VectorNotations.

Open Scope vector_scope.
Open Scope nat_scope.

Section HCOL_implementations.

  (* --- Type casts --- *)

  (* Promote scalar to unit vector *)
  Definition Vectorize (x:flags_m Rtheta): (mvector 1) := [x].

  (* Convert single element vector to scalar *)
  Definition Scalarize (x: mvector 1) : flags_m Rtheta := Vhead x.

  (* --- Scalar Product --- *)

  Definition ScalarProd 
             {n} (ab: (mvector n)*(mvector n)) : flags_m Rtheta :=
    match ab with
    | (a, b) => Vfold_right plus (Vmap2 mult a b) zero
    end.

  (* --- Infinity Norm --- *)
  Definition InfinityNorm
             {n} (v: mvector n) : flags_m Rtheta :=
    Vfold_right (Rtheta_liftM2 flags_m (max)) (Vmap abs v) zero.

  (* --- Chebyshev Distance --- *)
  Definition ChebyshevDistance 
             {n} (ab: (mvector n)*(mvector n)): flags_m Rtheta :=
    match ab with
    | (a, b) => InfinityNorm (Vmap2 (plus∘negate) a b)
    end.    

  (* --- Vector Subtraction --- *)
  Definition VMinus 
             {n} (ab: (mvector n)*(mvector n)) : mvector n := 
    match ab with
    | (a,b) => Vmap2 ((+)∘(-)) a b
    end.

  (* --- Monomial Enumerator --- *)

  Fixpoint MonomialEnumerator
           (n:nat) (x:flags_m Rtheta) {struct n} : mvector (S n) :=
    match n with 
    | O => [one]
    | S p => Vcons Rtheta_MSOne (Vmap (mult x) (MonomialEnumerator p x))
    end.

  (* --- Polynomial Evaluation --- *)

  Fixpoint EvalPolynomial {n} 
           (a: mvector n) (x:flags_m Rtheta) : flags_m Rtheta  :=
    match a with
      nil => Rtheta_MSZero
    | cons a0 p a' => plus a0 (mult x (EvalPolynomial a' x))
    end.

  (* === HCOL Basic Operators === *)
  (* Arity 2 function lifted to vectors. Also passes index as first parameter *)
  Definition BinOp
             (f: nat -> flags_m Rtheta -> flags_m Rtheta -> flags_m Rtheta)
             {n} (ab: (mvector n)*(mvector n))
    : mvector n :=
    match ab with
    | (a,b) =>  Vmap2Indexed f a b
    end.
  
  (* --- Induction --- *)

  Fixpoint Induction (n:nat) (f:flags_m Rtheta -> flags_m Rtheta -> flags_m Rtheta)
           (initial: flags_m Rtheta) (v: flags_m Rtheta) {struct n} : mvector n
    :=
    match n with 
    | O => []
    | S p => Vcons initial (Vmap (fun x => f x v) (Induction p f initial v))
    end.

  Fixpoint Inductor (n:nat) (f:flags_m Rtheta -> flags_m Rtheta -> flags_m Rtheta)
           (initial: flags_m Rtheta) (v:flags_m Rtheta) {struct n}
    : flags_m Rtheta :=
    match n with 
    | O => initial
    | S p => f (Inductor p f initial v) v
    end.

  (* --- Reduction --- *)

  (*  Reduction (fold) using single finction. In case of empty list returns 'id' value:
    Reduction f x1 .. xn b = f xn (f x_{n-1} .. (f x1 id) .. )
   *)
  Definition Reduction (f: flags_m Rtheta -> flags_m Rtheta -> flags_m Rtheta)
             {n} (id:flags_m Rtheta) (a: mvector n) : flags_m Rtheta
    := 
      Vfold_right f a id.

  (* --- Scale --- *)
  Definition Scale
             {n} (sv:(flags_m Rtheta)*(mvector n)) : mvector n :=
    match sv with
    | (s,v) => Vmap (mult s) v
    end.

  (* --- Concat ---- *)
  Definition Concat {an bn: nat} (ab: (mvector an)*(mvector bn)) : mvector (an+bn) :=
    match ab with
      (a,b) => Vapp a b
    end.

End HCOL_implementations.

(* === Lemmas about functions defined above === *)

Section HCOL_implementation_facts.

  Lemma Induction_cons:
    forall n initial (f:flags_m Rtheta -> flags_m Rtheta -> flags_m Rtheta)
      (v:flags_m Rtheta), 
      Induction (S n) f initial v = Vcons initial (Vmap (fun x => f x v) (Induction n f initial v)).
  Proof.
    intros; dep_destruct n; reflexivity.
  Qed.

  Lemma EvalPolynomial_0:
    forall (v:flags_m Rtheta), EvalPolynomial (Vnil) v = zero.
  Proof.
    intros; unfold EvalPolynomial.
    apply evalWriter_Rtheta_MSZero.
  Qed.

  (* TODO: better name. Maybe suffficent to replace with EvalPolynomial_cons *)
  Lemma EvalPolynomial_reduce:
    forall n (a: mvector (S n)) (x:flags_m Rtheta),
      EvalPolynomial a x  =
      plus (Vhead a) (mult x (EvalPolynomial (Vtail a) x)).
  Proof.
    intros; dep_destruct a; reflexivity.
  Qed.

  (* TODO: better name. Maybe suffficent to replace with ScalarProd_cons *)
  Lemma ScalarProd_reduce:
    forall n (ab: (mvector (S n))*(mvector (S n))),
      ScalarProd ab = plus (mult (Vhead (fst ab)) (Vhead (snd ab))) (ScalarProd (Ptail ab)).
  Proof.
    intros; dep_destruct ab.
    reflexivity.
  Qed.

  Lemma MonomialEnumerator_cons:
    forall n (x:flags_m Rtheta), 
      MonomialEnumerator (S n) x = Vcons one (Scale (x, (MonomialEnumerator n x))).
  Proof.
    assert(R: Rtheta_MSOne = one).
    {
      unfold equiv, Rtheta_Mequiv, Rtheta_MSOne.
      setoid_replace Rtheta_SOne with (@one Rtheta Rtheta_One).
      unfold_Rtheta_equiv.
      simpl.
      reflexivity.
      unfold_Rtheta_equiv.
      reflexivity.
    }
    intros n x.
    destruct n; simpl; repeat rewrite Vcons_to_Vcons_reord; rewrite R; reflexivity.
  Qed.

  Lemma ScalarProd_comm: forall n (a b: mvector n),
      ScalarProd (a,b) = ScalarProd (b,a).
  Proof.
    intros.
    unfold ScalarProd.
    rewrite 2!Vfold_right_to_Vfold_right_reord.
    rewrite Vmap2_comm.
    reflexivity.  
  Qed.

  (* Currently unused *)
  Lemma Scale_cons: forall n (s: flags_m Rtheta) (v: mvector (S n)),
      Scale (s,v) = Vcons (mult s (Vhead v)) (Scale (s, (Vtail v))).
  Proof.
    intros.
    unfold Scale.
    dep_destruct v.
    reflexivity.
  Qed.

  (* Scale distributivitiy *)
  (* Currently unused *)
  Lemma  Scale_dist: forall n a (b: mvector (S n)) (k: flags_m Rtheta),
      plus (mult k a) (Vhead (Scale (k,b))) = (mult k (plus a (Vhead b))).
  Proof.
    intros.
    unfold Scale.
    dep_destruct b.
    simpl.
    rewrite plus_mult_distr_l.
    reflexivity.
  Qed.

  Lemma ScalarProduct_descale: forall {n} (a b: mvector n) (s:flags_m Rtheta),
      [ScalarProd ((Scale (s,a)), b)] = Scale (s, [(ScalarProd (a,b))]).
  Proof.
    intros.
    unfold Scale, ScalarProd.
    simpl.
    induction n.
    Case "n=0".
    crush.
    VOtac.
    simpl.
    symmetry.
    destruct s. unfold equiv, vec_equiv, Vforall2, Vforall2_aux.
    split; try trivial.
    unfold mult, Rtheta_Mult,  equiv, Rtheta_val_equiv, Rtheta_rel_first.
    apply mult_0_r.
    Case "S(n)".
    VSntac a.  VSntac b.
    simpl.
    symmetry.
    rewrite Vcons_to_Vcons_reord, plus_mult_distr_l, <- Vcons_to_Vcons_reord.    

    (* Remove cons from IHn *)
    assert (HIHn:  forall a0 b0 : mvector n, equiv (Vfold_right plus (Vmap2 mult (Vmap (mult s) a0) b0) zero)
                                              (mult s (Vfold_right plus (Vmap2 mult a0 b0) zero))).
    {
      intros.
      rewrite <- Vcons_single_elim.
      apply IHn.
    }
    clear IHn.

    rewrite 2!Vcons_to_Vcons_reord,  HIHn.

    setoid_replace (mult s (mult (Vhead a) (Vhead b))) with (mult (mult s (Vhead a)) (Vhead b))
      by apply mult_assoc.
    reflexivity.
  Qed.

  Lemma ScalarProduct_hd_descale: forall {n} (a b: mvector n) (s:Rtheta),
      ScalarProd ((Scale (s,a)), b) = Vhead (Scale (s, [(ScalarProd (a,b))])).
  Proof.
    intros.
    apply hd_equiv with (u:=[ScalarProd ((Scale (s,a)),b)]).
    apply ScalarProduct_descale.
  Qed.

End HCOL_implementation_facts.

Section HCOL_implementation_proper.

  Global Instance Scale_proper `{!Proper (Rtheta_equiv ==> Rtheta_equiv ==> Rtheta_equiv) mult} (n:nat):
    Proper ((=) ==> (=))
           (Scale (n:=n)).
  Proof.
    intros x y Ex.
    destruct x as [xa xb]. destruct y as [ya yb].
    destruct Ex as [H0 H1].
    simpl in H0, H1.
    unfold Scale.
    induction n.
    Case "n=0".
    VOtac.
    reflexivity.
    Case "S n".
    
    dep_destruct xb.  dep_destruct yb.  split.
    assert (HH: h=h0) by apply H1.
    rewrite HH, H0.
    reflexivity.
    
    setoid_replace (Vmap (mult xa) x) with (Vmap (mult ya) x0).
    replace (Vforall2_aux equiv (Vmap (mult ya) x0) (Vmap (mult ya) x0))
    with (Vforall2 equiv (Vmap (mult ya) x0) (Vmap (mult ya) x0)).
    reflexivity.
    
    unfold Vforall2. reflexivity.
    
    apply IHn. clear IHn.
    apply H1.
  Qed.
  
  Global Instance ScalarProd_proper (n:nat):
    Proper ((=) ==> (=))
           (ScalarProd (n:=n)).
  Proof.
    intros x y Ex.
    destruct x as [xa xb].
    destruct y as [ya yb].
    unfold ScalarProd.
    rewrite 2!Vfold_right_to_Vfold_right_reord.
    destruct Ex as [H0 H1].
    simpl in H0, H1.
    rewrite H0, H1.
    reflexivity.
  Qed.
  
  Global Instance InfinityNorm_proper {n:nat}:
    Proper ((=) ==> (=))
           (InfinityNorm (n:=n)).
  Proof.
    unfold Proper.
    intros a b E1.
    unfold InfinityNorm.
    rewrite 2!Vfold_right_to_Vfold_right_reord.
    rewrite 2!Vmap_to_Vmap_reord.
    rewrite E1.
    reflexivity.
  Qed.

  Global Instance BinOp_proper
         {n:nat}
         (f : nat->flags_m Rtheta -> flags_m Rtheta -> flags_m Rtheta) `{pF: !Proper ((=) ==> (=) ==> (=) ==> (=)) f}:
    Proper ((=) ==> (=)) (@BinOp f n).
  Proof.
    intros a b Ea.
    unfold BinOp.
    destruct a. destruct b.
    destruct Ea as [E1 E2]. simpl in *.
    rewrite E1, E2.
    reflexivity.
  Qed.
  
  Global Instance Reduction_proper
         {n:nat} (f : flags_m Rtheta -> flags_m Rtheta -> flags_m Rtheta)
         `{pF: !Proper ((=) ==> (=) ==>  (=)) f}:
    Proper ((=) ==> (=) ==> (=)) (@Reduction f n).
  Proof.
    unfold Proper.
    intros a b E1 x y E2.
    unfold Reduction.
    rewrite 2!Vfold_right_to_Vfold_right_reord.
    rewrite E1, E2.
    reflexivity.
  Qed.
  
  Global Instance ChebyshevDistance_proper  (n:nat):
    Proper ((=) ==> (=))  (ChebyshevDistance (n:=n)).
  Proof.
    intros p p' pE.
    dep_destruct p.
    dep_destruct p'.
    unfold ChebyshevDistance.
    inversion pE. clear pE. simpl in *.
    clear p p'.
    rewrite H, H0.
    reflexivity.
  Qed.
  
  Global Instance EvalPolynomial_proper (n:nat):
    Proper ((=) ==> (=) ==> (=))  (EvalPolynomial (n:=n)).
  Proof.
    intros v v' vE a a' aE.
    induction n.
    VOtac.
    reflexivity.
    rewrite 2!EvalPolynomial_reduce.
    dep_destruct v.
    dep_destruct v'.
    simpl.
    apply Vcons_equiv_elim in vE.
    destruct vE as [HE xE].
    setoid_replace (EvalPolynomial x a) with (EvalPolynomial x0 a')
      by (apply IHn; assumption).
    rewrite HE, aE.
    reflexivity.
  Qed.

  Global Instance MonomialEnumerator_proper (n:nat):
    Proper ((=) ==> (=))  (MonomialEnumerator n).
  Proof.
    intros a a' aE.
    induction n.
    reflexivity.  
    rewrite 2!MonomialEnumerator_cons, 2!Vcons_to_Vcons_reord, IHn, aE.
    reflexivity.
  Qed.

  Global Instance Induction_proper
         (f:flags_m Rtheta -> flags_m Rtheta -> flags_m Rtheta)`{pF: !Proper ((=) ==> (=) ==> (=)) f} (n:nat):
    Proper ((=) ==> (=) ==> (=))  (@Induction n f).
  Proof.
    intros ini ini' iniEq v v' vEq.
    induction n.
    reflexivity.
    
    rewrite 2!Induction_cons, 2!Vcons_to_Vcons_reord, 2!Vmap_to_Vmap_reord.
    assert (RP: Proper (Rtheta_val_equiv ==> Rtheta_val_equiv) (λ x, f x v)) by solve_proper.
    rewrite IHn,  iniEq.

    assert (EE: ext_equiv (λ x, f x v)  (λ x, f x v')).
    {
      unfold ext_equiv.
      intros z z' zE.
      rewrite vEq, zE.
      reflexivity.
    }
    
    rewrite EE.
    reflexivity.
  Qed.

  Global Instance VMinus_proper (n:nat):
    Proper ((=) ==> (=))
           (@VMinus n).
  Proof.
    intros a b E.
    unfold VMinus.
    repeat break_let.
    destruct E as [E1 E2]; simpl in *.
    rewrite E1, E2.
    reflexivity.
  Qed.
  
End HCOL_implementation_proper.

Close Scope nat_scope.
Close Scope vector_scope.
