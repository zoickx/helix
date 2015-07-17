
Require Import Spiral.
Require Import SVector.
Require Import HCOL.
Require Import SigmaHCOL.
Require Import HCOLSyntax.

Require Import Arith.
Require Import Compare_dec.
Require Import Coq.Arith.Peano_dec.
Require Import Program. 

Require Import CpdtTactics.
Require Import CaseNaming.
Require Import Coq.Logic.FunctionalExtensionality.

(* CoRN MathClasses *)
Require Import MathClasses.interfaces.abstract_algebra MathClasses.interfaces.orders.
Require Import MathClasses.orders.minmax MathClasses.orders.orders MathClasses.orders.rings.
Require Import MathClasses.theory.rings MathClasses.theory.abs.

(*  CoLoR *)
Require Import CoLoR.Util.Vector.VecUtil.
Import VectorNotations.

Section SigmaHCOLRewriting.
  Context

    `{Ae: Equiv A}
    `{Az: Zero A} `{A1: One A}
    `{Aplus: Plus A} `{Amult: Mult A} 
    `{Aneg: Negate A}
    `{Ale: Le A}
    `{Alt: Lt A}
    `{Ato: !@TotalOrder A Ae Ale}
    `{Aabs: !@Abs A Ae Ale Az Aneg}
    `{Asetoid: !@Setoid A Ae}
    `{Aledec: !∀ x y: A, Decision (x ≤ y)}
    `{Aeqdec: !∀ x y, Decision (x = y)}
    `{Altdec: !∀ x y: A, Decision (x < y)}
    `{Ar: !Ring A}
    `{ASRO: !@SemiRingOrder A Ae Aplus Amult Az A1 Ale}
    `{ASSO: !@StrictSetoidOrder A Ae Alt}
  .

  Add Ring RingA: (stdlib_ring_theory A).
  
  Open Scope vector_scope.
  Open Scope nat_scope.


  (*
Motivating example:

BinOp(2, Lambda([ r4, r5 ], sub(r4, r5)))

-->

ISumUnion(i3, 2,
  ScatHUnion(2, 1, i3, 1) o
  BinOp(1, Lambda([ r4, r5 ], sub(r4, r5))) o
  GathH(4, 2, i3, 2)
)

    BinOp := (self, o, opts) >> When(o.N=1, o, let(i := Ind(o.N),
        ISumUnion(i, i.range, OLCompose(
        ScatHUnion(o.N, 1, i, 1),
        BinOp(1, o.op),
        GathH(2*o.N, 2, i, o.N)
        )))),

   *)

  Lemma cast_vector_operator_OK_OK: forall i0 i1 o0 o1 (v: vector A i1)
                                      (op: vector A i0 → svector A o0)
    ,
      (i0 ≡ i1 /\ o0 ≡ o1) -> is_OK ((cast_vector_operator
                                      i0 o0
                                      i1 o1
                                      (OK ∘ op)) v).
  Proof.
    intros.
    destruct H as [Hi Ho].
    rewrite <- Ho. clear o1 Ho.
    revert op.
    rewrite Hi. clear i0 Hi.
    intros.

    unfold compose.
    set (e := (λ x : vector A i1, @OK (vector (option A) o0) (op x))).

    assert(is_OK (e v)).
    unfold e. simpl. trivial.
    revert H.
    generalize dependent e. clear op.
    intros.

    rename i1 into i.
    rename o0 into o.
    (* here we arrived to more generic form of the lemma, stating that is_OK property is preserved by 'cast_vector_operator *)

    unfold cast_vector_operator.
    destruct (eq_nat_dec o o), (eq_nat_dec i i); try congruence.

    compute.
    destruct e0.
    dep_destruct e1.
    auto.
  Qed.
  
  Lemma BinOpIsDense: forall o st
                        (f:A->A->A) `{pF: !Proper ((=) ==> (=) ==> (=)) f}
                        (x: svector A (o+o)),
      svector_is_dense x -> 
      is_OK (evalSigmaHCOL st (SHOBinOp o f) x).
  Proof.
    intros. simpl.
    unfold evalBinOp.
    apply dense_casts_OK in H.
    destruct (try_vector_from_svector x).
    apply cast_vector_operator_OK_OK. omega.
    contradiction.
  Qed.

  (* Checks preconditoins of evaluation of SHOGathH to make sure it succeeds*)
  Lemma GathPre: forall (i o nbase nstride: nat) (base stride:aexp) (st:state)
                   (x: svector A i),
      ((evalAexp st base ≡ OK nbase) /\
       (evalAexp st stride ≡ OK nstride) /\
       nstride ≢ 0 /\
       o ≢ 0 /\
       (nbase+o*nstride) < i) ->
      is_OK (evalSigmaHCOL st (SHOGathH (i:=i) (o:=o) base stride) x).
  Proof.
    intros i o nbase nstride base stride st x.
    simpl.
    unfold evalGathH.
    crush.
    destruct (Compare_dec.lt_dec (nbase + o * nstride) i), o, nstride; 
    try match goal with
        | [ H: 0 ≡ 0 -> False |- _ ] => contradiction H; reflexivity
        | [ |- is_OK (OK _) ] => unfold is_OK; trivial
        | [ H0: ?P ,  H1: ~?P |- _] => contradiction
    end.
  Qed.


  Require Import Coq.Numbers.Natural.Peano.NPeano.


  (* Mapping from input indices to output ones.
This might be applicable in SPIRAL, since operators usually
never write to same element of the output vector more than once,
and some element of input vector can map to more than one element
of output vectors. 

In other words, functions on indices are:
1. injective (every element of the codomain is mapped to by at most one element of the domain)
1. non-surjective (NOT: if every element of the codomain is mapped to by at least one element of the domain)
   *)
  Definition GathForwardMap
             (base stride: nat)
             {snz: 0 ≢ stride} (i:nat): (option nat)
    := match lt_dec i base with
       | left _ => None
       | right _ => match divmod (i-base) stride 0 stride with
                   | (o, O) => Some o
                   | _ => None
                   end
       end.

  (* Because it never returns NONE it means output vector is dense! *)
  Definition GathBackwardMap
             (base stride: nat)
             {snz: 0 ≢ stride} (o:nat): (option nat)
    := Some (base + o*stride).
  
  Definition opt_nat_max (x:option nat) (y: option nat): option nat :=
    match x, y with
    | None, None => None
    | None, Some y' => Some y'
    | Some x', None => Some x'
    | Some x', Some y' => Some (max x'  y')
    end.

  Definition opt_nat_lt (x:option nat) (y: nat): Prop :=
    match x with
    | None => True
    | Some x' =>  x' < y
    end.
  
  Definition IndexMapUpperBound
             (f: nat -> (option nat))
             (i: nat) :=
    Vfold_left opt_nat_max None (Vmap f (natrange i)).

  Lemma ibound_relax_by_1
        {i o: nat}
        {f: nat -> (option nat)} :
    (forall (n:nat), n< (S o) ->  opt_nat_lt (f n) i) -> (forall (n:nat), n<o ->  opt_nat_lt (f n) i).
  Proof.
    crush.
  Qed.
  
  (* Build operator on vectors by mapping outputs to inputs
via provided (output_index -> input_index) function *)
  Fixpoint vector_index_backward_operator
           {i o: nat}
           (f: nat -> (option nat))
           {ibound: forall (n:nat), n<o ->  opt_nat_lt (f n) i}
           (x: svector A i):  (svector A o) :=
    (match o return nat -> (forall (n:nat), n<o ->  opt_nat_lt (f n) i) -> (svector A o) with 
    | 0 => fun _ _ => Vnil
    | S p => fun no ib =>
      snoc (vector_index_backward_operator (o:=p)
                                                 (ibound := ibound_relax_by_1 ib) f x)
                 match f p with
                 | None => None
                 | Some a' =>
                   match lt_dec a' i with
                   | left ip => Vnth x ip
                   | right _ => None (* this should never happen *)
                   end
                 end
    end) o ibound.
  
  
(*  
  Lemma GathIndexMapUpperBound
        (base stride i: nat)
        {snz: 0 ≢ stride}:
    (OptMapUpperBound (GathIndexMap (snz:=snz) base stride) i)= Some (modulo (i-base) stride) \/ (OptMapUpperBound (GathIndexMap (snz:=snz) base stride) i) = None.
  Proof.
    induction i.
    right. 
    reflexivity.

    unfold OptMapUpperBound.

    assert ((natrange (S i)) ≡ snoc (natrange i) i).
    
  Qed.
*)
  
  Lemma GathInvariant: forall (i o nbase nstride: nat)
                         (base stride:aexp) (st:state)
                         (x: svector A i) (y: svector A o)
                         (n:nat) (HY: n<o) (HX: (nbase + n*nstride) < i)
                         (snz: nstride ≢ 0) (nnz: o ≢ 0)
                         (HO: (nbase + o*nstride) < i)
    ,
      (evalAexp st base ≡ OK nbase) ->
      (evalAexp st stride ≡ OK nstride) ->
      (evalSigmaHCOL st (SHOGathH (i:=i) (o:=o) base stride) x) ≡ OK y ->
      Vnth x HX ≡ Vnth y HY.
  Proof.
    simpl.
    intros. 

    revert H1.
    unfold evalGathH.
    rewrite H0, H.

    case (eq_nat_dec 0 nstride).
    intros. symmetry in e. contradiction.
    intros Hsnz. 

    case (eq_nat_dec 0 o).
    intros. congruence.
    intros Hnnz.
    
    case (Compare_dec.lt_dec (nbase + o * nstride) i).
    Focus 2. congruence.
    intros HD. clear HO. (* HO = HD *)

    
    intros. injection H1. clear H1.
    intros.
    (* rewrite <- H1. *)
 
    dependent induction n.
    Case "n=0".
    destruct y.
    SCase "y=[]".
    crush.
    SCase "y<>[]".
    rewrite Vnth_cons_head; try reflexivity.
  Qed.

        
  Lemma GathIsMap: forall (i o: nat) (base stride:aexp) (st:state)
                            (y: svector A o)
                            (x: svector A i),
      (evalSigmaHCOL st (SHOGathH (i:=i) (o:=o) base stride) x) ≡ OK y ->
      Vforall (Vin_aux x) y.
  Proof.
    intros.







    
    intros i o base stride st y x.

    unfold evalSigmaHCOL, evalGathH. simpl.
    (*assert ((SigmaHCOL_Operators.GathH i o nbase nstride x) ≡ y).
    injection y. *)
    
    induction y.
        
    intros. apply Vforall_nil.
 
    unfold evalSigmaHCOL, evalGathH. simpl.
    intros.
    rewrite <- Vforall_cons.
    split.
    admit.
    apply IHy.
  Qed.
        
  (* Gath on dense vector produces dense vector *)
  Lemma GathDenseIsDense: forall (i o nbase nstride: nat) (base stride:aexp) (st:state)
                            (y: svector A o)
                            (x: svector A i),
      svector_is_dense x -> 
      (evalSigmaHCOL st (SHOGathH (i:=i) (o:=o) base stride) x) ≡ OK y ->
      svector_is_dense y.
  Proof.
    intros.
    inversion H0.
    revert H2.
    unfold evalGathH.

    
  Qed.
  
  Definition ASub: A -> A -> A := (plus∘negate).
 
  Global Instance ASub_proper:
    Proper ((=) ==> (=) ==> (=)) (ASub).
  Proof.
    intros a a' aE b b' bE.
    unfold ASub.
    rewrite aE, bE.
    reflexivity.
  Qed.

  Definition op1 := SHOBinOp 2 ASub.
  Definition vari := AValue (Var "i").
  Definition c2 := AConst 2.
  Definition c0 := AConst 0.
  
  Definition op2 :=
    SHOISumUnion (Var "i") c2
                 (SHOCompose _ _
                             (SHOScatHUnion (o:=2) vari c2)
                             (SHOCompose _ _ 
                                         (SHOBinOp 1 ASub)
                                         (SHOGathH (i:=4) (o:=2) vari c2))).

  Lemma testOp2Op1: forall (st : state) (x : vector (option A) (2 + 2)),
      svector_is_dense x -> evalSigmaHCOL st op1 x = evalSigmaHCOL st op2 x.
  Proof.
    intros.
    unfold equiv, maybeError_equiv, op1.
    assert (op1OK: is_OK (evalSigmaHCOL st (SHOBinOp 2 ASub) x)) by (apply BinOpIsDense; assumption).

    case_eq (evalSigmaHCOL st (SHOBinOp 2 ASub) x); intros; simpl in H0, op1OK.

    Focus 2.
    rewrite H0 in op1OK.
    contradiction.

    unfold op2.
    
  Qed.
  
  Section SigmaHCOLRewriting.
