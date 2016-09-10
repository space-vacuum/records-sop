{-# LANGUAGE TypeInType, TypeFamilies, GADTs, DataKinds, PolyKinds, TypeOperators #-}
{-# LANGUAGE MultiParamTypeClasses, FlexibleInstances, ScopedTypeVariables #-}
{-# LANGUAGE StandaloneDeriving, FlexibleContexts, UndecidableInstances #-}
{-# LANGUAGE DeriveGeneric, DuplicateRecordFields #-}
{-# LANGUAGE RankNTypes, ConstraintKinds #-}
module SubTyping where

import Data.Proxy
-- import Generics.SOP
import Generics.SOP.BasicFunctors
import Generics.SOP.Constraint
import Generics.SOP.GGP
import Generics.SOP.NP
import Generics.SOP.NS
import Generics.SOP.Universe
import Generics.SOP.Sing
import Generics.SOP.Type.Metadata
import qualified GHC.Generics as GHC
import GHC.Types
import Unsafe.Coerce

-- Idea for an actually convenient interface:
--
-- Have three levels of representation.
--
-- The "full" level contains all info.
--
-- The "medium" level contains only the names of constructors and fields.
--
-- SOP P2 xss = NS (NP P2 `Compose` P2) xss
--
-- Code:
--
-- MCode MyRec1 =
--   '[ '( "MyRec1", '[ '( "rint", Int ), '( "rbool", Bool ) ] ]

-- from :: Generic a => a -> Rep a

data MyRec1 = MyRec1 { rint :: Int, rbool :: Bool }
  deriving (GHC.Generic, Show)

data MyRec2 = MyRec2 { rbool :: Bool, rchar :: Char, rint :: Int }
  deriving (GHC.Generic, Show)

instance Generic MyRec1
instance HasDatatypeInfo MyRec1

instance Generic MyRec2
instance HasDatatypeInfo MyRec2

cast ::
     ( Generic a, Generic b
     , Code a ~ '[ ca ], Code b ~ '[ cb ]
     , siga ~ RecordSigOf a, sigb ~ RecordSigOf b
     , Strip siga ~ ca, Strip sigb ~ cb
     , Combine (Labels siga) ca ~ siga
     , Combine (Labels sigb) cb ~ sigb
     , IsSubTypeOf siga sigb
     )
  => a -> b
cast = fromRecord . coerce . toRecord

toRecord :: (Generic a, Code a ~ '[ x ], r ~ RecordSigOf a, Strip r ~ x, Combine (Labels r) x ~ r) => a -> Record r
toRecord = repToRecord . unZ . unSOP . from

repToRecord :: (xs ~ Strip sig, Combine (Labels sig) xs ~ sig) => NP I xs -> Record sig
repToRecord = unsafeCoerce
{-
repToRecord Nil = Nil
repToRecord (I x :* xs) = P2 x :* repToRecord xs
-}

recordToRep :: forall xs sig . (xs ~ Strip sig, Combine (Labels sig) xs ~ sig, SListI xs) => Record sig -> NP I xs
recordToRep = unsafeCoerce
{-
recordToRep = case sList :: SList xs of
  SNil  -> const Nil
  SCons -> \ r -> case r of
    P2 x :* xs -> I x :* recordToRep xs
-}

fromRecord :: (Generic a, Code a ~ '[ x ], r ~ RecordSigOf a, Strip r ~ x, Combine (Labels r) x ~ r) => Record r -> a
fromRecord = to . SOP . Z . recordToRep

type family Strip (r :: RecordSig) :: [Type] where
  Strip '[] = '[]
  Strip ( '(_, a) : sig ) = a : Strip sig

type family Labels (r :: RecordSig) :: [Symbol] where
  Labels '[] = '[]
  Labels ( '(l, _) : sig ) = l : Labels sig

type family Combine (ss :: [Symbol]) (ts :: [Type]) :: RecordSig where
  Combine _ '[] = '[]
  Combine ss (t : ts) = '(Head ss, t) : Combine (Tail ss) ts

type family Head (xs :: [k]) :: k where
  Head (x : xs) = x

type family Tail (xs :: [k]) :: [k] where
  Tail (x : xs) = xs

type RecordSigOf a = ToRecordSig (DatatypeInfoOf a) (Code a)

type family ToRecordSig (d :: DatatypeInfo) (c :: [[Type]]) :: RecordSig where
  ToRecordSig (ADT _ _ cis)    c = ToRecordSigC cis c
  ToRecordSig (Newtype _ _ ci) c = ToRecordSigC '[ ci ] c

type family ToRecordSigC (cis :: [ConstructorInfo]) (c :: [[Type]]) :: RecordSig where
  ToRecordSigC '[ 'Record _ fis ] '[ ts ] = ToRecordSigF fis ts

type family ToRecordSigF (fis :: [FieldInfo]) (c :: [Type]) :: RecordSig where
  ToRecordSigF '[] '[] = '[]
  ToRecordSigF ( 'FieldInfo l : fis ) ( t : ts ) = '(l, t) : ToRecordSigF fis ts

type FieldLabel = Symbol
type RecordSig = [(FieldLabel, Type)]

newtype P2 (p :: (a, Type)) = P2 (Snd p)

type Record (r :: RecordSig) = NP P2 r

type family Snd (p :: (a, b)) :: b where
  Snd '(a, b) = b

class IsSubTypeOf (r1 :: RecordSig) (r2 :: RecordSig) where
  coerce :: Record r1 -> Record r2

instance IsSubTypeOf r1 '[] where
  coerce _ = Nil

instance (IsSubTypeOf r1 rs2, Contains r1 s2 a2) => IsSubTypeOf r1 ( '(s2, a2) : rs2 ) where
  coerce r = P2 (get (Proxy :: Proxy s2) r) :* coerce r

-- | TODO. Can we reuse GHC.OverloadedLabels.IsLabel or similar?
class Contains (r :: RecordSig) (s :: Symbol) (a :: Type) where
  get :: Proxy s -> Record r -> a

{-
instance {-# OVERLAPPING #-} (a1 ~ a2) => Contains ( '(s, a1) : rs ) s a2 where
  get _ (P2 a :* _) = a

instance {-# OVERLAPPABLE #-} Contains rs s2 a2 => Contains ( '(s1, a1) : rs ) s2 a2 where
  get p (_ :* r) = get p r
-}

test1 :: Record '[ '( "name", String ), '( "age", Int ) ]
test1 = P2 "Andres" :* P2 99 :* Nil

data DFoo x where MkDFoo :: x ~ (y : ys) => DFoo x

-- Sub-project
--
-- A proper form of type-equality witnessing in order to bypass
-- overlapping instances.

-- What we want to be able to write:

instance
  IfThenElse (IsEqual s1 s2) (a1 ~ a2) (Contains rs s2 a2) =>
  Contains ( '(s1, a1) : rs ) s2 a2 where
  get p (P2 a :* r) =
    ifthenelse (Proxy :: Proxy '(IsEqual s1 s2, a1 ~ a2, Contains rs s2 a2))
      a
      (get p r)

class IfThenElse (b :: Bool) (t :: Constraint) (e :: Constraint) where
  ifthenelse :: Proxy '(b, t, e) -> (t => r) -> (e => r) -> r

instance t => IfThenElse True t e where
  ifthenelse _ t _ = t

instance e => IfThenElse False t e where
  ifthenelse _ _ e = e

{-
data YesNo (a :: Type) (b :: Bool) where
  Yes :: a -> YesNo a True

data IfThenElse (b :: Bool) (t :: Type) (e :: Type) where
  Then :: t -> IfThenElse True  t e
  Else :: e -> IfThenElse False t e
-}

type family IsEqual (a :: k) (b :: k) :: Bool where
  IsEqual a a = True
  IsEqual a b = False

{-
class CIfThenElse (b :: Bool) (t :: Type) (e :: Type) where
  ifthenelse :: IfThenElse b t e

type family IfEq (a :: k) (b :: k) (t :: l) (e :: l) where
  IfEq a a t e = t
  IfEq a b t e = e
-}
