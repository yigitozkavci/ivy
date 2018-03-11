{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings     #-}
{-# LANGUAGE ScopedTypeVariables   #-}

module Ivy.Codegen.Memory where

--------------------------------------------------------------------------------
import           Control.Lens hiding (ix, op)
import           Control.Monad
import           Data.Function (on)
import           Data.List (find, groupBy)
import qualified Data.Map as M
import           Data.Monoid
--------------------------------------------------------------------------------
import           Ivy.Codegen.Types
import           Ivy.EvmAPI.Instruction
import           Ivy.Syntax
--------------------------------------------------------------------------------

class MemoryM m where
  storeAddressed
    :: Integer -- Address of the value. Value should be loaded from this address
    -> Integer -- Address to put value on
    -> m ()
  load
    :: Integer
    -> m ()
  storeVal
    :: Integer -- Actual value
    -> Integer -- Address to put value on
    -> m ()
  alloc
    :: Size
    -> m Integer
  store
    :: m ()
  push
    :: Integer
    -> m ()
  allocBulk
    :: Integer
    -> Size
    -> m Integer

instance MemoryM Evm where
  storeAddressed valAddr destAddr = do
    -- Initial state
    load valAddr
    op (PUSH32 destAddr)
    store

  load addr = do
    op (PUSH32 addr)
    op MLOAD

  storeVal val destAddr = do
    op (PUSH32 val)
    op (PUSH32 destAddr)
    store

  store =
    op MSTORE

  alloc size = do
    pointer <- use memPointer
    mem <- use memory
    let (Just addr) = flip find [pointer..] $ \ix ->
          case M.lookup ix mem of
            Nothing -> True
            Just _  -> False
    memory %= M.insert addr size
    memPointer .= addr
    pure (addr * 0x20)

  push val =
    op (PUSH32 val) -- OPTIMIZE: different PUSH variants can be used for this task

  allocBulk len size = do
    pointer <- use memPointer
    mem <- use memory
    let group_existence :: [[(Integer, Maybe Size)]] =
          groupBy ((==) `on` snd)
          $ map (\ix -> (ix, M.lookup ix mem))
          $ [pointer..]
    let (Just cellGroup) = flip find group_existence $ \cells ->
          case take (fromIntegral len) cells of
            [] -> False
            ((_, Just _):_) -> False -- These are filled cells
            suitable ->
              if fromIntegral (length suitable) >= len
                 then True
                 else False

    let (startAddr, _) = head cellGroup
    forM_ [startAddr..(startAddr + len - 1)] $ \addr -> memory %= M.update (const (Just size)) addr
    pure (startAddr * 0x20)

totalMemBlockSize :: Integer
totalMemBlockSize = 32 -- There are 32 bytes in a block

calcAddr :: Integer -> Integer -> Integer
calcAddr ix allocLen = ix * totalMemBlockSize + allocLen

sizeof :: PrimType -> Size
sizeof TInt  = Size_8
sizeof TChar = Size_1
sizeof TBool = Size_1
sizeof other = error $ "`sizeof` is not implemented for type " <> show other

initMemory :: M.Map Integer Size
initMemory = M.empty

boolToInt :: Bool -> Integer
boolToInt True  = 1
boolToInt False = 0

{-|
Given the size and necessary stack state, stores that much byte properly aligned.
For instance, we want to store 2 bytes of data at 0x0000, so we have the following stack:

00000000
327024A6

And the iterative process:

00000003
327024A6

-> MSTORE8

00000002
00327024

-> MSTORE8

00000001
00003270

-> MSTORE8

00000000
00000032

-> MSTORE8

-> EXIT

-}
sizeInt :: Size -> Integer
sizeInt Size_1  = 1
sizeInt Size_2  = 2
sizeInt Size_4  = 4
sizeInt Size_8  = 8
sizeInt Size_32 = 32
