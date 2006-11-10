module FrontEnd.Tc.Kind(
    Kind(..),
    KBase(..),
    Kindvar(..),
    KindConstraint(..),
    kindCombine,
    kindStar,
    kindUTuple,
    kindFunRet,
    kindHash,
    kindArg,
    unfoldKind
    ) where

import Data.Monoid
import Control.Monad
import Data.IORef

import Binary
import Doc.DocLike
import Doc.PPrint(pprint,PPrint)
import Name.Name

{-

 KQuest = ?        star or hash or unboxed tuple
 KQuestQuest = ??  star or hash
 KUTuple = (#)     unboxed tuple
 Star    = *       boxed value
 KHash   = #       unboxed value
 Kfun    = (->)
 KNamed Foo = Foo  named kind

 we have the following subkinding going on

       ?
      / \
     ?? (#)
     /\
    *  #

in addition, user defined named kinds are allowed. these can only occur via
kind annotations, and only unify with themselves

-}

data KBase =
        Star
        | KHash
        | KUTuple
        | KQuestQuest
        | KQuest
        | KNamed Name
    deriving(Eq, Ord)   -- but we need them for kind inference
    {-! derive: GhcBinary !-}

kindStar   = KBase Star
kindHash   = KBase KHash
kindUTuple = KBase KUTuple
kindFunRet = KBase KQuest
kindArg    = KBase KQuestQuest

data Kind  = KBase KBase
           | Kfun Kind Kind
           | KVar Kindvar               -- variables aren't really allowed in haskell in kinds
             deriving(Eq, Ord)   -- but we need them for kind inference
    {-! derive: GhcBinary !-}


kindCombine :: Monad m => Kind -> Kind -> m Kind
kindCombine x y = g x y where
    f x y | x == y = return x

    f KQuest x = fquest x
    f x  KQuest = fquest x
    f KQuestQuest x = fquest2 x
    f x  KQuestQuest = fquest2 x
    f x y = fail $ "kindCombine: " ++ show (x,y)
    fquest (KNamed n) = fail $ "Attempt to unify named kind" <+> tshow n <+> "with ?"
    fquest x = return x
    fquest2 (KNamed n) = fail $ "Attempt to unify named kind" <+> tshow n <+> "with ??"
    fquest2 KUTuple = fail $ "Attempt to unify unboxed tuple with ??"
    fquest2 KQuest = return KQuestQuest
    fquest2 x = return x
    g (KBase x) (KBase y) = f x y >>= return . KBase
    g (Kfun a b) (Kfun a' b') = return Kfun `ap` g a a' `ap` g b b'
    g x y = fail $ "kindCombine: " ++ show (x,y)

data KindConstraint
    = KindSimple     -- ^ * | kindSimple -> kindSimple
    | KindQuest      -- ^ ?, so * or (#) or #
    | KindQuestQuest -- ^ ??, * or #
    | KindStar       -- ^ must be *
    | KindAny        -- ^ may be anything
    deriving(Eq,Ord,Show)

-- note that named kinds are never infered, so we don't need constraints
-- mentioning them.

instance Monoid KindConstraint where
    mempty = KindAny
    mappend a b | a == b = a
    mappend KindAny k = k
    mappend KindStar _ = KindStar
    mappend KindSimple KindQuest = KindStar
    mappend KindSimple KindQuestQuest = KindStar
    mappend KindQuest KindQuestQuest = KindQuestQuest
    mappend k1 k2 = mappend k2 k1

data Kindvar = Kindvar {
    kvarUniq :: !Int,
    kvarRef :: IORef (Maybe Kind),
    kvarConstraint :: KindConstraint
    }

instance Binary Kindvar where
    put_ _ _ = return ()
    get _ = return (error "Binary.Kindvar.get")

instance Eq Kindvar where
    a == b = kvarUniq a == kvarUniq b
instance Ord Kindvar where
    a `compare` b = kvarUniq a `compare` kvarUniq b

instance Show Kind where
    showsPrec _ k = pprint k

instance Show Kindvar where
    showsPrec _ k = pprint k


instance Show KBase where
    showsPrec _ Star    = showString "*"
    showsPrec _ KUTuple = showString "(#)"
    showsPrec _ KHash   = showString "#"
    showsPrec _ KQuest  = showString "?"
    showsPrec _ KQuestQuest = showString "??"
    showsPrec _ (KNamed n) = shows n

instance DocLike d => PPrint d KBase where
    pprint kb = text (show kb)

instance DocLike d => PPrint d Kind where
   pprint (KBase b) = pprint b
   pprint (KVar kindVar)   = pprint kindVar
   pprint (Kfun (KBase b) k2)   = pprint b <+> text "->" <+> pprint k2
   pprint (Kfun (KVar b)  k2)   = pprint b <+> text "->" <+> pprint k2
   pprint (Kfun k1   b) = text "(" <> pprint k1 <> text ")" <+> text "->" <+> pprint b
--   pprint (Kfun k1   (KVar b)) = text "(" <> pprint k1 <> text ")" <+> text "->" <+> pprint b
--   pprint (Kfun k1   k2)   = text "(" <> pprint k1 <> text ") -> (" <> pprint k2 <> text ")"

instance DocLike d =>  PPrint d Kindvar where
   pprint Kindvar { kvarUniq = s } = text $ 'k':show s

--  * -> * == [*,*]
--  (*->*->*) -> * -> * == [(*->*->*), *, *]
unfoldKind :: Kind -> [Kind]
unfoldKind (Kfun k1 k2) = k1 : unfoldKind k2
unfoldKind v = [v]
