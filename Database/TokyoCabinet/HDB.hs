module Database.TokyoCabinet.HDB
    (
    -- * error type and utility
      TCErrorCode
    , errmsg
    , eSUCCESS
    , eTHREAD
    , eINVALID
    , eNOFILE
    , eNOPERM
    , eMETA
    , eRHEAD
    , eOPEN
    , eCLOSE
    , eTRUNC
    , eSYNC
    , eSTAT
    , eSEEK
    , eREAD
    , eWRITE
    , eMMAP
    , eLOCK
    , eUNLINK
    , eRENAME
    , eMKDIR
    , eRMDIR
    , eKEEP
    , eNOREC
    , eMISC
     -- * open mode
    , oREADER
    , oWRITER
    , oCREAT
    , oTRUNC
    , oNOLOCK
    , oLCKNB
    , oTSYNC
    , OpenMode
    -- * tuning options
    , tLARGE
    , tDEFLATE
    , tBZIP
    , tTCBS
    , tEXCODEC
    , TuningOption
    -- * basic API
    , new
    , delete
    , ecode
    , tune
    , setcache
    , setxmsiz
    , open
    , close
    , put
    , putkeep
    , putcat
    , putasync
    , out
    , get
    , vsiz
    , iterinit
    , iternext
    , fwmkeys
    , addint
    , adddouble
    , sync
    , optimize
    , vanish
    , copy
    , tranbegin
    , trancommit
    , tranabort
    , path
    , rnum
    , fsiz
    , TCHDB
    )
    where

import Foreign.C.Types (CInt)
import Foreign.C.String

import Foreign.Ptr
import Foreign.Storable (peek)
import Foreign.ForeignPtr
import Foreign.Marshal (alloca)
import Foreign.Marshal.Utils (maybePeek)

import Data.Int
import Data.Bits

import Database.TokyoCabinet.HDB.C
import Database.TokyoCabinet.Error
import qualified Database.TokyoCabinet.Storable as S

combineOpenMode :: [OpenMode] -> OpenMode
combineOpenMode = OpenMode . foldr ((.|.) . unOpenMode) 0

combineTuningOption :: [TuningOption] -> TuningOption
combineTuningOption = TuningOption . foldr ((.|.) . unTuningOption) 0

data TCHDB = TCHDB !(ForeignPtr HDB)

new :: IO TCHDB
new = do ptr <- c_tchdbnew
         fptr <- newForeignPtr tchdbFinalizer ptr
         return $ TCHDB fptr

delete :: TCHDB -> IO ()
delete (TCHDB fptr) = finalizeForeignPtr fptr

ecode :: TCHDB -> IO TCErrorCode
ecode (TCHDB fptr) = withForeignPtr fptr $ \p -> do
                       e <- c_tchdbecode p
                       return $ TCErrorCode e

tune :: TCHDB -> Int64 -> Int8 -> Int8 -> [TuningOption] -> IO Bool
tune (TCHDB fptr) bnum apow fpow options =
    let option = unTuningOption $ combineTuningOption options
    in withForeignPtr fptr $ \p -> c_tchdbtune p bnum apow fpow option

setcache :: TCHDB -> Int32 -> IO Bool
setcache (TCHDB fptr) rcnum = withForeignPtr fptr $ \p -> c_tchdbsetcache p rcnum

setxmsiz :: TCHDB -> Int64 -> IO Bool
setxmsiz (TCHDB fptr) xmsiz = withForeignPtr fptr $ \p -> c_tchdbsetxmsiz p xmsiz

open :: TCHDB -> String -> [OpenMode] -> IO Bool
open (TCHDB fptr) name modes = 
    withForeignPtr fptr $ \p ->
        withCString name $ \c_name ->
            c_tchdbopen p c_name option
    where option = unOpenMode $ combineOpenMode modes

close :: TCHDB -> IO Bool
close (TCHDB fptr) = withForeignPtr fptr c_tchdbclose

type PutFunc = Ptr HDB -> CString -> CInt -> CString -> CInt -> IO Bool

liftPutFunc ::
    (S.Storable a, S.Storable b) => PutFunc -> TCHDB -> a -> b -> IO Bool
liftPutFunc func (TCHDB fptr) key val =
    withForeignPtr fptr $ \p ->
        S.withPtrLen key $ \(kbuf, ksize) ->
        S.withPtrLen val $ \(vbuf, vsize) ->
            func p kbuf (fromIntegral ksize) vbuf (fromIntegral vsize)

put :: (S.Storable a, S.Storable b) => TCHDB -> a -> b -> IO Bool
put = liftPutFunc c_tchdbput

putkeep :: (S.Storable a, S.Storable b) => TCHDB -> a -> b -> IO Bool
putkeep = liftPutFunc c_tchdbputkeep

putcat :: (S.Storable a, S.Storable b) => TCHDB -> a -> b -> IO Bool
putcat = liftPutFunc c_tchdbputcat

putasync :: (S.Storable a, S.Storable b) => TCHDB -> a -> b -> IO Bool
putasync = liftPutFunc c_tchdbputasync

out :: (S.Storable a) => TCHDB -> a -> IO Bool
out (TCHDB fptr) key =
    withForeignPtr fptr $ \p ->
        S.withPtrLen key $ \(kbuf, ksiz) ->
            c_tchdbout p kbuf (fromIntegral ksiz)

get :: (S.Storable a, S.Storable b) => TCHDB -> a -> IO (Maybe b)
get (TCHDB fptr) key =
    withForeignPtr fptr $ \p ->
        S.withPtrLen key $ \(kbuf, ksiz) ->
            alloca $ \sizbuf -> do
                vbuf <- c_tchdbget p kbuf (fromIntegral ksiz) sizbuf
                flip maybePeek vbuf $ \vp ->
                    do siz <- peek sizbuf
                       S.peekPtrLen (vp, fromIntegral siz)

vsiz :: (S.Storable a) => TCHDB -> a -> IO (Maybe Int)
vsiz (TCHDB fptr) key =
    withForeignPtr fptr $ \p ->
        S.withPtrLen key $ \(kbuf, ksiz) -> do
          vsize <- c_tchdbvsiz p kbuf (fromIntegral ksiz)
          return $ if vsize == -1
                     then Nothing
                     else Just (fromIntegral vsize)

iterinit :: TCHDB -> IO Bool
iterinit (TCHDB fptr) = withForeignPtr fptr c_tchdbiterinit

iternext :: (S.Storable a) => TCHDB -> IO (Maybe a)
iternext (TCHDB fptr) =
    withForeignPtr fptr $ \p ->
        alloca $ \sizbuf -> do
            vbuf <- c_tchdbiternext p sizbuf
            flip maybePeek vbuf $ \vp ->
                do siz <- peek sizbuf
                   S.peekPtrLen (vp, fromIntegral siz)

fwmkeys :: (S.Storable a, S.Storable b) => TCHDB -> a -> Int -> IO [b]
fwmkeys = undefined

addint :: (S.Storable a) => TCHDB -> a -> Int -> IO Int
addint (TCHDB fptr) key num =
    withForeignPtr fptr $ \p ->
        S.withPtrLen key $ \(kbuf, ksiz) -> do
            n <- c_tchdbaddint p kbuf (fromIntegral ksiz) (fromIntegral num)
            return $ fromIntegral n

adddouble :: (S.Storable a) => TCHDB -> a -> Double -> IO Double
adddouble (TCHDB fptr) key num =
    withForeignPtr fptr $ \p ->
        S.withPtrLen key $ \(kbuf, ksiz) -> do
            n <- c_tchdbadddouble p kbuf (fromIntegral ksiz) (realToFrac num)
            return $ realToFrac n

sync :: TCHDB -> IO Bool
sync (TCHDB fptr) = withForeignPtr fptr c_tchdbsync

optimize :: TCHDB -> Int64 -> Int8 -> Int8 -> [TuningOption] -> IO Bool
optimize (TCHDB fptr) bnum apow fpow options = 
    let option = unTuningOption $ combineTuningOption options
    in withForeignPtr fptr $ \p -> c_tchdboptimize p bnum apow fpow option

vanish :: TCHDB -> IO Bool
vanish (TCHDB fptr) = withForeignPtr fptr c_tchdbvanish

copy :: TCHDB -> String -> IO Bool
copy (TCHDB fptr) pathname =
    withForeignPtr fptr $ \p ->
        withCString pathname $ \c_pathname ->
            c_tchdbcopy p c_pathname

tranbegin :: TCHDB -> IO Bool
tranbegin (TCHDB fptr) = withForeignPtr fptr c_tchdbtranbegin

trancommit :: TCHDB -> IO Bool
trancommit (TCHDB fptr) = withForeignPtr fptr c_tchdbtrancommit

tranabort :: TCHDB -> IO Bool
tranabort (TCHDB fptr) = withForeignPtr fptr c_tchdbtranabort

path :: TCHDB -> IO (Maybe String)
path (TCHDB fptr) =
    withForeignPtr fptr $ \p -> do
      cstr <- c_tchdbpath p
      maybePeek peekCString cstr

rnum :: TCHDB -> IO Int64
rnum (TCHDB fptr) = withForeignPtr fptr c_tchdbrnum

fsiz :: TCHDB -> IO Int64
fsiz (TCHDB fptr) = withForeignPtr fptr c_tchdbfsiz