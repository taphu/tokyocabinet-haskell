module TestUtil where
import Test.HUnit
import System.Directory
import Control.Monad
import Control.Exception

setupFile :: FilePath -> IO String
setupFile fn =
  doesFileExist fn >>=
  flip when (assertFailure ("setupFile: (" ++ fn ++ ") already exists!")) >>
  return fn

teardownFile :: String -> IO ()
teardownFile fn = doesFileExist fn >>= flip when (removeFile fn)

withoutFile :: String -> (String -> IO a) -> IO a
withoutFile fn = bracket (setupFile fn) teardownFile

