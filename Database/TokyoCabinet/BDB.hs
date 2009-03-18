module Database.TokyoCabinet.BDB
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
    , oNOLCK
    , oLCKNB
    , oTSYNC
    , OpenMode
    -- * tuning option
    , tLARGE
    , tDEFLATE
    , tBZIP
    , tTCBS
    , tEXCODEC
    , TuningOption
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
    , putdup
    , putlist
    , out
    , outlist
    , get
    , getlist
    , vnum
    , vsiz
    , range
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
    , TCBDB
    ) where

import Data.Int
import Data.Word
import Data.Bits

import Foreign.C.Types
import Foreign.C.String
import Foreign.Ptr
import Foreign.ForeignPtr
import Foreign.Storable (peek)
import Foreign.Marshal (alloca)
import Foreign.Marshal.Utils (maybePeek)

import Database.TokyoCabinet.Error
import Database.TokyoCabinet.BDB.C
import Database.TokyoCabinet.Internal
import qualified Database.TokyoCabinet.Storable as S

combineTuningOption :: [TuningOption] -> TuningOption
combineTuningOption = TuningOption . foldr ((.|.) . unTuningOption) 0

data TCBDB = TCBDB !(ForeignPtr BDB)

new :: IO TCBDB
new = do
  bdb <- c_tcbdbnew
  TCBDB `fmap` newForeignPtr tcbdbFinalizer bdb

delete :: TCBDB -> IO ()
delete (TCBDB bdb) = finalizeForeignPtr bdb

ecode :: TCBDB -> IO TCErrorCode
ecode (TCBDB bdb) = TCErrorCode `fmap` withForeignPtr bdb c_tcbdbecode

tune :: TCBDB -> Int32 -> Int32
     -> Int64 -> Int8 -> Int8 -> [TuningOption] -> IO Bool
tune (TCBDB bdb) lmemb nmemb bnum apow fpow opts =
    withForeignPtr bdb $ \bdb' ->
        c_tcbdbtune bdb' lmemb nmemb bnum apow fpow opt
    where
      opt = unTuningOption $ combineTuningOption opts

setcache :: TCBDB -> Int32 -> Int32 -> IO Bool
setcache (TCBDB bdb) lcnum ncnum =
    withForeignPtr bdb $ \bdb' -> c_tcbdbsetcache bdb' lcnum ncnum

setxmsiz :: TCBDB -> Int64 -> IO Bool
setxmsiz (TCBDB bdb) xmsiz =
    withForeignPtr bdb $ \bdb' -> c_tcbdbsetxmsiz bdb' xmsiz

open :: TCBDB -> String -> [OpenMode] -> IO Bool
open (TCBDB bdb) fpath modes =
    withForeignPtr bdb $ \bdb' ->
        withCString fpath $ \fpath' -> c_tcbdbopen bdb' fpath' mode
    where
      combineOpenMode = OpenMode . foldr ((.|.) . unOpenMode) 0
      mode = unOpenMode $ combineOpenMode modes

close :: TCBDB -> IO Bool
close (TCBDB bdb) = withForeignPtr bdb c_tcbdbclose

type PutFunc = Ptr BDB -> Ptr Word8 -> CInt -> Ptr Word8 -> CInt -> IO Bool
liftPutFunc ::
    (S.Storable a, S.Storable b) => PutFunc -> TCBDB -> a -> b -> IO Bool
liftPutFunc func (TCBDB bdb) key val =
    withForeignPtr bdb $ \bdb' ->
        S.withPtrLen key $ \(kbuf, ksize) ->
        S.withPtrLen val $ \(vbuf, vsize) ->
            func bdb' (castPtr kbuf) (fromIntegral ksize)
                      (castPtr vbuf) (fromIntegral vsize)

put :: (S.Storable a, S.Storable b) => TCBDB -> a -> b -> IO Bool
put = liftPutFunc c_tcbdbput

putkeep :: (S.Storable a, S.Storable b) => TCBDB -> a -> b -> IO Bool
putkeep = liftPutFunc c_tcbdbputkeep

putcat :: (S.Storable a, S.Storable b) => TCBDB -> a -> b -> IO Bool
putcat = liftPutFunc c_tcbdbputcat

putdup :: (S.Storable a, S.Storable b) => TCBDB -> a -> b -> IO Bool
putdup = liftPutFunc c_tcbdbputdup

putlist :: (S.Storable a, S.Storable b) => TCBDB -> a -> [b] -> IO Bool
putlist bdb key vals = do
  and `fmap` mapM (putdup bdb key) vals

out :: (S.Storable a) => TCBDB -> a -> IO Bool
out (TCBDB bdb) key =
    withForeignPtr bdb $ \bdb' ->
        S.withPtrLen key $ \(kbuf, ksize) ->
            c_tcbdbout bdb' (castPtr kbuf) (fromIntegral ksize)

outlist :: (S.Storable a) => TCBDB -> a -> IO Bool
outlist (TCBDB bdb) key =
    withForeignPtr bdb $ \bdb' ->
        S.withPtrLen key $ \(kbuf, ksize) ->
            c_tcbdbout3 bdb' (castPtr kbuf) (fromIntegral ksize)

get :: (S.Storable a, S.Storable b) => TCBDB -> a -> IO (Maybe b)
get (TCBDB bdb) key =
    withForeignPtr bdb $ \bdb' ->
        S.withPtrLen key $ \(kbuf, ksize) ->
            alloca $ \sizbuf -> do
                ptr <- c_tcbdbget bdb' (castPtr kbuf)
                           (fromIntegral ksize) sizbuf
                siz <- peek sizbuf
                flip maybePeek ptr $ \p ->
                    S.peekPtrLen (castPtr p, fromIntegral siz)

getlist :: (S.Storable a, S.Storable b) => TCBDB -> a -> IO [b]
getlist (TCBDB bdb) key =
    withForeignPtr bdb $ \bdb' ->
        S.withPtrLen key $ \(kbuf, ksize) -> do
          ptr <- c_tcbdbget4 bdb' (castPtr kbuf) (fromIntegral ksize)
          if ptr == nullPtr
            then return []
            else peekTCListAndFree ptr

vnum :: (S.Storable a) => TCBDB -> a -> IO (Maybe Int)
vnum (TCBDB bdb) key =
    withForeignPtr bdb $ \bdb' ->
        S.withPtrLen key $ \(kbuf, ksize) -> do
            res <- c_tcbdbvnum bdb' (castPtr kbuf) (fromIntegral ksize)
            return $ if res == 0
                       then Nothing
                       else Just $ fromIntegral res

vsiz :: (S.Storable a) => TCBDB -> a -> IO (Maybe Int)
vsiz (TCBDB bdb) key =
    withForeignPtr bdb $ \bdb' ->
        S.withPtrLen key $ \(kbuf, ksize) -> do
            res <- c_tcbdbvsiz bdb' (castPtr kbuf) (fromIntegral ksize)
            return $ if res == -1
                       then Nothing
                       else Just $ fromIntegral res

range :: (S.Storable a)
         => TCBDB -> Maybe a -> Bool
                  -> Maybe a -> Bool -> Int -> IO [a]
range (TCBDB bdb) bkey binc ekey einc maxn =
    withForeignPtr bdb $ \bdb' ->
        withPtrLen' bkey $ \(bkbuf, bksiz) ->
        withPtrLen' ekey $ \(ekbuf, eksiz) ->
            c_tcbdbrange bdb' (castPtr bkbuf) (fromIntegral bksiz) binc
                              (castPtr ekbuf) (fromIntegral eksiz) einc
                                              (fromIntegral maxn)
                                                  >>= peekTCListAndFree
    where
      withPtrLen' (Just key) action = S.withPtrLen key action
      withPtrLen' Nothing action = action (nullPtr, 0)

fwmkeys :: (S.Storable a) => TCBDB -> a -> Int -> IO [a]
fwmkeys (TCBDB bdb) prefix maxn =
    withForeignPtr bdb $ \bdb' ->
        S.withPtrLen prefix $ \(pbuf, psiz) ->
            c_tcbdbfwmkeys bdb' (castPtr pbuf) (fromIntegral psiz)
                           (fromIntegral maxn) >>= peekTCListAndFree

addint :: (S.Storable a) => TCBDB -> a -> Int -> IO Int
addint (TCBDB bdb) key num =
    withForeignPtr bdb $ \bdb' ->
        S.withPtrLen key $ \(kbuf, ksiz) ->
            fromIntegral `fmap` c_tcbdbaddint bdb' (castPtr kbuf)
                                    (fromIntegral ksiz) (fromIntegral num)

adddouble :: (S.Storable a) => TCBDB -> a -> Double -> IO Double
adddouble (TCBDB bdb) key num =
    withForeignPtr bdb $ \bdb' ->
        S.withPtrLen key $ \(kbuf, ksiz) ->
            realToFrac `fmap` c_tcbdbadddouble bdb' (castPtr kbuf)
                                  (fromIntegral ksiz) (realToFrac num)

sync :: TCBDB -> IO Bool
sync (TCBDB bdb) = withForeignPtr bdb c_tcbdbsync

optimize :: TCBDB -> Int32 -> Int32
         -> Int64 -> Int8 -> Int8 -> [TuningOption] -> IO Bool
optimize (TCBDB bdb) lmemb nmemb bnum apow fpow opts =
    withForeignPtr bdb $ \bdb' ->
        c_tcbdboptimize bdb' lmemb nmemb bnum apow fpow opt
    where
      opt = unTuningOption $ combineTuningOption opts

vanish :: TCBDB -> IO Bool
vanish (TCBDB bdb) = withForeignPtr bdb c_tcbdbvanish

copy :: TCBDB -> String -> IO Bool
copy (TCBDB bdb) fpath =
    withForeignPtr bdb $ \bdb' -> withCString fpath (c_tcbdbcopy bdb')

tranbegin :: TCBDB -> IO Bool
tranbegin (TCBDB bdb) = withForeignPtr bdb c_tcbdbtranbegin

trancommit :: TCBDB -> IO Bool
trancommit (TCBDB bdb) = withForeignPtr bdb c_tcbdbtrancommit

tranabort :: TCBDB -> IO Bool
tranabort (TCBDB bdb) = withForeignPtr bdb c_tcbdbtranabort

path :: TCBDB -> IO (Maybe String)
path (TCBDB bdb) =
    withForeignPtr bdb $ \bdb' -> do
        fpath <- c_tcbdbpath bdb'
        maybePeek peekCString fpath

rnum :: TCBDB -> IO Int64
rnum (TCBDB bdb) = withForeignPtr bdb c_tcbdbrnum

fsiz :: TCBDB -> IO Int64
fsiz (TCBDB bdb) = withForeignPtr bdb c_tcbdbfsiz
