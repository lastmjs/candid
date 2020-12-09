(*
MiniCandid: A formalization of the core ideas of Candid
*)

Require Import Coq.ZArith.BinInt.
Require Import Coq.Init.Datatypes.

Require Import Coq.Relations.Relation_Operators.
Require Import Coq.Relations.Relation_Definitions.
Require Import Coq.Relations.Operators_Properties.

Set Bullet Behavior "Strict Subproofs".
Set Default Goal Selector "!".

(* Loads the idiosyncratic CaseNames extension *)
Require Import candid.NamedCases.
Set Printing Goal Names. (* Coqide doesn’t use it yet, will be in 8.13 *)

(* Types are coinductive (we do not want to model the graph structure explicilty) *)
CoInductive T :=
  | NatT: T
  | IntT: T
  | NullT : T
  | OptT : T -> T
  | VoidT : T
  | ReservedT : T
  .

Inductive V :=
  | NatV : nat -> V
  | IntV : Z -> V
  | NullV : V
  | SomeV : V -> V
  | ReservedV : V
  .

(* This is a stand in for `~(null <: t)` in places
where <: is not allowed yet. *)
Definition is_opt_like_type (t : T) : bool :=
  match t with
  | NullT => true
  | OptT _ => true
  | ReservedT => true
  | _ => false
  end.
  
Definition is_not_opt_like_value (v : V) : Prop :=
match v with
| NullV => False
| SomeV _ => False
| ReservedV => False
| _ => True
end.

(* The boring, non-subtyping typing relation. *)
Inductive HasType : V -> T -> Prop :=
  | NatHT:
    case natHT,
    forall n, NatV n :: NatT
  | IntHT:
    case intHT,
    forall n, IntV n :: IntT
  | NullHT:
    case nullHT,
    NullV :: NullT
  | NullOptHT:
    case nullOptHT,
    forall t, NullV :: OptT t
  | OptHT:
    case optHT,
    forall v t, v :: t -> SomeV v :: OptT t
  | ReservedHT:
    case reservedHT,
    ReservedV :: ReservedT
where "v :: t" := (HasType v t).


Module NoOpportunisticDecoding.

(*
This is the variant without `t <: opt t'`, where
things can be simple and inductive.
*)

Reserved Infix "<:" (at level 80, no associativity).
CoInductive Subtype : T -> T -> Prop :=
  | ReflST :
    case reflSL,
    forall t, t <: t
  | NatIntST :
    case natIntSL,
    NatT <: IntT
  | NullOptST :
    case nullOptST,
    forall t, NullT <: OptT t
  | OptST :
    case optST,
    forall t1 t2,
    (* This additional restriction added to fix https://github.com/dfinity/candid/issues/146 *)
    (is_opt_like_type t1 = is_opt_like_type t2) -> 
    t1 <: t2 ->
    OptT t1 <: OptT t2
  | ConstituentOptST :
    case constituentOptST,
    forall t1 t2,
    is_opt_like_type t2 = false ->
    t1 <: t2 -> t1 <: OptT t2
  | VoidST :
    case voidST,
    forall t, VoidT <: t
  | ReservedST :
    case reservedST,
    forall t, t <: ReservedT
where "t1 <: t2" := (Subtype t1 t2).



Reserved Notation "v1 ~> v2 :: t" (at level 80, v2 at level 50, no associativity).
Inductive Coerces : V -> V -> T -> Prop :=
  | NatC: 
    case natC,
    forall n, NatV n ~> NatV n :: NatT
  | IntC:
    case intC,
    forall n, IntV n ~> IntV n :: IntT
  | NatIntC:
    case natIntC,
    forall n i, i = Z.of_nat n -> (NatV n ~> IntV i :: IntT)
  | NullC:
    case nullC,
    NullV ~> NullV :: NullT
  | NullOptC:
    case nullOptC,
    forall t, NullV ~> NullV :: OptT t
  | SomeOptC:
    case someOptC,
    forall v1 v2 t,
    v1 ~> v2 :: t ->
    SomeV v1 ~> SomeV v2 :: OptT t
  | ConstituentOptC:
    case constituentC,
    forall v1 v2 t,
    is_not_opt_like_value v1 ->
    v1 ~> v2 :: t ->
    v1 ~> SomeV v2 :: OptT t
  | ReservedC:
    case reservedC,
    forall v1,
    v1 ~> ReservedV :: ReservedT
where "v1 ~> v2 :: t" := (Coerces v1 v2 t).

(* The is_not_opt_like_type definition is only introduced because
   Coq (and not only coq) does not like hyptheses like ~(null <: t)
*)
Lemma is_not_opt_like_type_correct:
  forall t,
  is_opt_like_type t = true <-> NullT <: t.
Proof.
  intros. destruct t; simpl; intuition.
  all: try inversion H.
  all: try named_constructor.
Qed.

Theorem coercion_correctness:
  forall v1 v2 t, v1 ~> v2 :: t -> v2 :: t.
Proof.
  intros. induction H; constructor; assumption.
Qed.

Theorem coercion_roundtrip:
  forall v t, v :: t -> v ~> v :: t.
Proof.
  intros. induction H; constructor; intuition.
Qed.

Theorem coercion_uniqueness:
  forall v v1 v2 t, v ~> v1 :: t -> v ~> v2 :: t -> v1 = v2.
Proof.
  intros.
  revert v2 H0.
  induction H; intros v2' Hother;
    try (inversion Hother; subst; clear Hother; try congruence; firstorder congruence).
Qed.

Theorem soundness_of_subtyping:
  forall t1 t2,
  t1 <: t2 ->
  forall v1, v1 :: t1 -> exists v2, v1 ~> v2 :: t2.
Proof.
  intros t1 t2 Hsub v HvT. revert t2 Hsub.
  induction HvT; intros t1 Hsub; inversion Hsub; subst; clear Hsub;
    name_cases;
    try (eexists;constructor; try constructor; fail).
  [natHT_constituentOptST]: {
    inversion H0; subst; clear H0; simpl in H; inversion H.
    - eexists. named_constructor; [constructor|named_constructor].
    - eexists. named_constructor; [constructor|named_constructor;reflexivity].
  }
  [intHT_constituentOptST]: {
    inversion H0; subst; clear H0; simpl in H; inversion H.
    econstructor. named_econstructor; [constructor|named_constructor].
  }
  [optHT_reflSL]: {
    specialize (IHHvT t (ReflST _ _)).
    destruct IHHvT as [v2 Hv2].
    eexists. named_econstructor; try eassumption.
  }
  [optHT_optST]: {
    specialize (IHHvT _ H1).
    destruct IHHvT as [v2 Hv2].
    eexists; named_econstructor; eassumption.
  }
  [optHT_constituentOptST]: {
    inversion H0; subst; clear H0; simpl in H; inversion H.
  }
  [reservedHT_constituentOptST]: {
    inversion H0; subst; clear H0; simpl in H; inversion H.
  }
Qed.

Theorem subtyping_refl: reflexive _ Subtype.
Proof. intros x. apply ReflST; constructor. Qed.

Lemma is_not_opt_like_type_contravariant:
  forall t1 t2,
     is_opt_like_type t1 = false -> t2 <: t1 -> is_opt_like_type t2 = false.
Proof. intros. destruct t1, t2; easy. Qed.

Theorem subtyping_trans: transitive _ Subtype.
Proof.
  cofix Hyp.
  intros t1 t2 t3 H1 H2.
  inversion H1; subst; clear H1;
  inversion H2; subst; clear H2;
    name_cases;
    try (constructor; easy).
  [natIntSL_constituentOptST]: {
    named_constructor.
    - assumption.
    - eapply Hyp; [named_econstructor | assumption].
  }
  [optST_optST0]: {
    named_constructor.
    - congruence.
    - eapply Hyp; eassumption.
  }
  [optST_constituentOptST]: {
    inversion H3; subst; clear H3; simpl in H1; congruence.
  }
  [constituentOptST_optST]: {
    named_constructor.
    - congruence.
    - firstorder.
  }
  [constituentOptST_constituentOptST0]: {
    inversion H3; subst; clear H3; try easy.
  }
  [reservedST_constituentOptST]: {
    inversion H0; subst; clear H0; inversion H.
  }
Qed.

End NoOpportunisticDecoding.


Module OpportunisticDecoding.
(*
This is the variant with `t <: opt t'.
*)

Reserved Infix "<:" (at level 80, no associativity).
CoInductive Subtype : T -> T -> Prop :=
  | ReflST :
    case reflSL,
    forall t, t <: t
  | NatIntST :
    case natIntSL,
    NatT <: IntT
  | OptST :
    case optST,
    forall t1 t2,
    t1 <: OptT t2
  | VoidST :
    case voidST,
    forall t, VoidT <: t
  | ReservedST :
    case reservedST,
    forall t, t <: ReservedT
where "t1 <: t2" := (Subtype t1 t2).

(*
The coercion relation is not strictly positive, so we have to implement
it as a function that recurses on the value. This is essentially
coercion function, and we can separately try to prove that it corresponds
to the relation.
 *)


Require Import FunInd.
Function coerce (n : nat) (v1 : V) (t : T) : option V :=
  match n with  | 0 => None (* out of fuel *) | S n => 
    match v1, t with
    | NatV n, NatT => Some (NatV n)
    | IntV n, IntT => Some (IntV n)
    | NatV n, IntT => Some (IntV (Z.of_nat n))
    | NullV, NullT => Some NullV
    | NullV, OptT t => Some NullV
    | SomeV v, OptT t => option_map SomeV (coerce n v t)
    | ReservedV, OptT t => Some NullV
    | v, OptT t =>
      if is_opt_like_type t
      then None
      else option_map SomeV (coerce n v t)
    | v, ReservedT => Some ReservedV
    | v, t => None
    end
  end.
  
Definition Coerces (v1 v2 : V) (t : T) : Prop :=
  exists n, coerce n v1 t = Some v2.
Notation "v1 ~> v2 :: t" := (Coerces v1 v2 t) (at level 80, v2 at level 50, no associativity).

(* TODO: derive intro and elim rules *)

(* The is_not_opt_like_type definition is only introduced because
   Coq (and not only coq) does not like hyptheses like ~(null <: t)
*)
Lemma is_not_opt_like_type_correct:
  forall t,
  is_opt_like_type t = true <-> NullT <: t.
Proof.
  intros. destruct t; simpl; intuition.
  all: try inversion H.
  all: try named_constructor.
Qed.

Theorem coercion_correctness:
  forall v1 v2 t, v1 ~> v2 :: t -> v2 :: t.
Proof.
  intros.
  inversion H as [n Hcoerce]; clear H.
  revert v1 v2 t Hcoerce.
  induction n; intros v1 v2 t Hcoerce;
    functional inversion Hcoerce; subst;
    try (named_constructor; fail).
  * destruct (coerce n v t1) eqn:Heq; simpl in H0; inversion H0; subst; clear H0.
    specialize (IHn _ _ _ Heq).
    named_constructor; assumption. 
  * destruct (coerce n v1 t1) eqn:Heq; simpl in H0; inversion H0; subst; clear H0.
    specialize (IHn _ _ _ Heq).
    named_constructor; assumption. 
Qed.

Theorem coercion_roundtrip:
  forall v t, v :: t -> v ~> v :: t.
Proof.
  intros. induction H; 
    try (exists 1; reflexivity).
  * destruct IHHasType as [n Hcoerce].
    exists (S n). simpl. rewrite Hcoerce. reflexivity.
Qed.

Theorem coercion_uniqueness:
  forall v v1 v2 t, v ~> v1 :: t -> v ~> v2 :: t -> v1 = v2.
Proof.
  intros.
  revert v2 H0.
  induction H; intros v2' Hother;
    try (inversion Hother; subst; clear Hother; try congruence; firstorder congruence).
  * destruct Hother as [n Hother].
    admit.
Admitted.

Theorem soundness_of_subtyping:
  forall t1 t2,
  t1 <: t2 ->
  forall v1, v1 :: t1 -> exists v2, v1 ~> v2 :: t2.
Proof.
  intros t1 t2 Hsub v HvT. revert t2 Hsub.
  induction HvT; intros t1 Hsub; inversion Hsub; subst; clear Hsub;
    name_cases;
    try (eexists;constructor; try constructor; fail).
  [natHT_optST]: {
    admit.
  }
  [intHT_optST]: {
    admit.
  }
  [optHT_reflSL]: {
    specialize (IHHvT t (ReflST _ _)).
    destruct IHHvT as [v2 Hv2].
    eexists. named_econstructor; try eassumption.
  }
  [optHT_optST]: {
    admit.
  }
  [reservedHT_optST]: {
    admit.
  }
Admitted.

Theorem subtyping_refl: reflexive _ Subtype.
Proof. intros x. apply ReflST; constructor. Qed.

Lemma is_not_opt_like_type_contravariant:
  forall t1 t2,
     is_opt_like_type t1 = false -> t2 <: t1 -> is_opt_like_type t2 = false.
Proof. intros. destruct t1, t2; easy. Qed.

Theorem subtyping_trans: transitive _ Subtype.
Proof.
  cofix Hyp.
  intros t1 t2 t3 H1 H2.
  inversion H1; subst; clear H1;
  inversion H2; subst; clear H2;
    name_cases;
    try (constructor; easy).
Qed.

End OpportunisticDecoding.