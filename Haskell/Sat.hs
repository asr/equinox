module Sat where

import Foreign.C.Types       ( CInt )
import Foreign.C.String      ( CString, withCString )
import Foreign.Ptr           ( Ptr, nullPtr )
import Foreign.Storable      ( peek )
import Foreign.Marshal.Array ( withArray0, peekArray0 )
import Foreign.Marshal.Alloc ( malloc, free )
import System.IO             ( FilePath )
import Foreign.Storable      ( Storable )

----------------------------------------------------------------------------------------------------
-- types

newtype Lit = Lit CInt deriving (Eq, Num, Ord, Storable)

instance Show Lit where
    showsPrec i (Lit l) = showsPrec i l

instance Read Lit where
    readsPrec i = map (\ (x,r) -> (Lit x, r)) . readsPrec i

mkTrue     = Lit 1
mkFalse    = -mkTrue

newtype Solver     = Solver (Ptr ())
newtype MiniSatM a = MiniSatM (Solver -> IO a)

instance Monad MiniSatM where
    return x = MiniSatM (const (return x))
    (MiniSatM f) >>= g = MiniSatM (\s -> f s >>= \x -> case g x of { MiniSatM m -> m s })

instance Functor MiniSatM where
    fmap f (MiniSatM g) = MiniSatM (fmap f . g)

----------------------------------------------------------------------------------------------------
-- MiniSatM functions

lower :: MiniSatM a -> Solver -> IO a
lower (MiniSatM f) = f

withSolverLog :: FilePath -> (Solver -> IO a) -> IO a
withSolverLog log f = withCString log (flip withSolverPrim f)

withSolver :: (Solver -> IO a) -> IO a
withSolver = withSolverPrim nullPtr

withSolverPrim :: CString -> (Solver -> IO a) -> IO a
withSolverPrim log f =
    do s <- s_new log
       r <- f s
       s_delete s
       return r

{-
    mkLit       :: m Lit
    clause      :: [Lit] -> m Bool

    solve       :: [Lit] -> m Bool
    solve_      :: Bool  -> [Lit] -> m Bool
    modelValue  :: Lit   -> m Bool
    value       :: Lit   -> m (Maybe Bool)
    contr       :: m [Lit]
    okay        :: m Bool

    -- for convenience
    lift        :: IO a -> m a

    -- default *with* simplification
    solve = solve_ True

    freezeLit   :: Lit   -> m ()
    unfreezeLit :: Lit   -> m ()
    simplify    :: Bool -> Bool -> m Bool

    freezeLit   l = return ()
    unfreezeLit l = return ()
    simplify  x y = return True
    
    -- formula creation (with simple defaults)
    mkAnd       :: Lit -> Lit -> m Lit
    mkAnd       = defAnd

    mkOr        :: Lit -> Lit -> m Lit
    mkOr x y    = mkAnd (-x) (-y) >>= return . negate

    mkEqu       :: Lit -> Lit -> m Lit
    mkEqu       = defEqu

    mkXor       :: Lit -> Lit -> m Lit
    mkXor x y   = mkEqu (-x) (-y) >>= return . negate

    mkIte       :: Lit -> Lit -> Lit -> m Lit
    mkIte       = defIte

    mkAdd       :: Lit -> Lit -> Lit -> m (Lit, Lit)
    mkAdd       = defAdd
-}

mkLit         = MiniSatM s_newlit
clause ls     = fmap fromCBool $ MiniSatM (withArray0 (Lit 0) ls . s_clause)
solve_ b ls   = fmap fromCBool $ MiniSatM (withArray0 (Lit 0) ls . flip s_solve (toCBool b))

freezeLit l   = MiniSatM (\s -> s_freezelit s l)
unfreezeLit l = MiniSatM (\s -> s_unfreezelit s l)
modelValue l  = fmap fromCBool $ MiniSatM (flip s_modelvalue l)
value      l  = fmap fromLBool $ MiniSatM (flip s_value l)
contr         = MiniSatM (\s -> s_contr s >>= peekArray0 (Lit 0))
okay          = fmap fromCBool $ MiniSatM s_okay
simplify elim  turnoffelim = fmap fromCBool $ MiniSatM (\s -> s_simplify s (toCBool elim) (toCBool turnoffelim))

lift       f  = MiniSatM (const f)

mkAnd x y = MiniSatM (\s -> s_and s x y)
mkOr  x y = MiniSatM (\s -> s_or  s x y)
mkEqu x y = MiniSatM (\s -> s_equ s x y)
mkXor x y = MiniSatM (\s -> s_xor s x y)
mkIte x y z = MiniSatM (\s -> s_ite s x y z)
mkAdd x y z = MiniSatM $ \s -> 
    do cp <- malloc
       sp <- malloc
       s_add s x y z cp sp
       c  <- peek cp
       s  <- peek sp
       free cp
       free sp
       return (c,s)

verbose n = MiniSatM (\s -> s_verbose s (fromIntegral n))

nVars, nClauses, nConflicts, nRemembered :: MiniSatM Int
nVars       = fmap fromIntegral $ MiniSatM s_nvars
nClauses    = fmap fromIntegral $ MiniSatM s_nclauses
nConflicts  = fmap fromIntegral $ MiniSatM s_nconflicts
nRemembered = fmap fromIntegral $ MiniSatM s_nremembered

----------------------------------------------------------------------------------------------------
-- helpers

fromCBool :: CInt -> Bool
fromCBool 0 = False
fromCBool _ = True

-- should import the correct constants really
fromLBool :: CInt -> Maybe Bool
fromLBool 0    = Nothing
fromLBool 1    = Just True
fromLBool (-1) = Just False

toCBool :: Bool -> CInt
toCBool True  = 1
toCBool False = 0

----------------------------------------------------------------------------------------------------
-- foreign imports

foreign import ccall unsafe "static csolver.h"   s_new            :: CString -> IO Solver
foreign import ccall unsafe "static csolver.h"   s_delete         :: Solver -> IO () 
foreign import ccall unsafe "static csolver.h"   s_newlit         :: Solver -> IO Lit
foreign import ccall unsafe "static csolver.h"   s_clause         :: Solver -> Ptr Lit -> IO CInt
foreign import ccall unsafe "static csolver.h"   s_solve          :: Solver -> CInt -> Ptr Lit -> IO CInt
foreign import ccall unsafe "static csolver.h"   s_simplify       :: Solver -> CInt -> CInt -> IO CInt
foreign import ccall unsafe "static csolver.h"   s_freezelit      :: Solver -> Lit -> IO ()
foreign import ccall unsafe "static csolver.h"   s_unfreezelit    :: Solver -> Lit -> IO ()
foreign import ccall unsafe "static csolver.h"   s_setpolarity    :: Solver -> Lit -> IO ()
foreign import ccall unsafe "static csolver.h"   s_setdecisionvar :: Solver -> Lit -> CInt -> IO ()
foreign import ccall unsafe "static csolver.h"   s_value          :: Solver -> Lit -> IO CInt
foreign import ccall unsafe "static csolver.h"   s_and            :: Solver -> Lit -> Lit -> IO Lit
foreign import ccall unsafe "static csolver.h"   s_or             :: Solver -> Lit -> Lit -> IO Lit
foreign import ccall unsafe "static csolver.h"   s_equ            :: Solver -> Lit -> Lit -> IO Lit
foreign import ccall unsafe "static csolver.h"   s_xor            :: Solver -> Lit -> Lit -> IO Lit
foreign import ccall unsafe "static csolver.h"   s_ite            :: Solver -> Lit -> Lit -> Lit -> IO Lit
foreign import ccall unsafe "static csolver.h"   s_add            :: Solver -> Lit -> Lit -> Lit -> Ptr Lit -> Ptr Lit -> IO ()
foreign import ccall unsafe "static csolver.h"   s_modelvalue     :: Solver -> Lit -> IO CInt
foreign import ccall unsafe "static csolver.h"   s_contr          :: Solver -> IO (Ptr Lit)
foreign import ccall unsafe "static csolver.h"   s_verbose        :: Solver -> CInt -> IO ()
foreign import ccall unsafe "static csolver.h"   s_okay           :: Solver -> IO CInt
foreign import ccall unsafe "static csolver.h"   s_nvars          :: Solver -> IO CInt
foreign import ccall unsafe "static csolver.h"   s_nclauses       :: Solver -> IO CInt
foreign import ccall unsafe "static csolver.h"   s_nconflicts     :: Solver -> IO CInt
foreign import ccall unsafe "static csolver.h"   s_nremembered    :: Solver -> IO CInt
