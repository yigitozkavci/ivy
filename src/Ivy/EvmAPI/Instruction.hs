{-# LANGUAGE OverloadedStrings #-}

module Ivy.EvmAPI.Instruction where

--------------------------------------------------------------------------------
import           Control.Arrow
import           Control.Applicative
import           Control.Monad.Except
import           Control.Monad.Logger.CallStack (logInfo)
import           Control.Lens hiding (op)
import           Control.Monad.State
import           Control.Monad.Writer
import qualified Data.Text              as T
import           Text.Printf
--------------------------------------------------------------------------------
import           Ivy.Codegen.Types
import qualified Ivy.Syntax             as S
--------------------------------------------------------------------------------

data Instruction =
    STOP
  | ADD
  | MUL
  | SUB
  | DIV
  | POP
  | MLOAD
  | MSTORE
  | MSTORE8
  | JUMP
  | JUMPI
  | PC
  | JUMPDEST
  | PUSH1
  | PUSH2
  | PUSH32
  | DUP1
  | SWAP1
  | SWAP2
  | LOG0
  | LOG1
  | LOG2
  | RETURN

toInstrCode :: Instruction -> Integer
toInstrCode STOP = 0x00
toInstrCode ADD = 0x01
toInstrCode MUL = 0x02
toInstrCode SUB = 0x03
toInstrCode DIV = 0x04
toInstrCode POP = 0x50
toInstrCode MLOAD = 0x51
toInstrCode MSTORE = 0x52
toInstrCode MSTORE8 = 0x53
toInstrCode JUMP = 0x56
toInstrCode JUMPI = 0x57
toInstrCode PC = 0x58
toInstrCode JUMPDEST = 0x5b
toInstrCode PUSH1 = 0x60
toInstrCode PUSH2 = 0x61
toInstrCode PUSH32 = 0x7f
toInstrCode DUP1 = 0x80
toInstrCode SWAP1 = 0x90
toInstrCode SWAP2 = 0x91
toInstrCode LOG0 = 0xA0
toInstrCode LOG1 = 0xA1
toInstrCode LOG2 = 0xA2
toInstrCode RETURN = 0xf3

addBC :: Integer -> Evm ()
addBC val = byteCode <>= T.pack (printf "%064x" val)

op :: Instruction -> Evm ()
op instr = byteCode <>= T.pack (printf "%02x" (toInstrCode instr))

-- I forgot what this does after 10 minutes
op2 :: Instruction -> Integer -> Evm ()
op2 = curry ((op *** addBC) >>> uncurry (>>))

load
  :: Size
  -> Address
  -> Evm ()
load size addr = do
  op2 PUSH32 (0x10 ^ (64 - 2 * (sizeInt size)))
  logInfo $ "Loading with size: " <> T.pack (show (sizeInt size))
  op2 PUSH32 addr
  op MLOAD
  op DIV

storeAddressed
  :: Size    -- Variable size
  -> Integer -- Address of the value. Value should be loaded from this address
  -> Integer -- Address to put value on
  -> Evm ()
storeAddressed size valAddr destAddr = do
  load size valAddr
  op2 PUSH32 destAddr
  op MSTORE8

storeVal
  :: Size    -- Variable size
  -> Integer -- Address of the value. Value should be loaded from this address
  -> Integer -- Address to put value on
  -> Evm ()
storeVal size val destAddr = do
  op2 PUSH32 val
  op2 PUSH32 destAddr
  op MSTORE8

-- store :: Size -> Evm ()
-- store Size_1 = op MSTORE8
-- store Size_32 = op MSTORE
-- store other = throwError $ InternalError $ "Cannot store " <> show other <> " bytes, it's not implemented."

binOp :: S.PrimType -> Instruction -> Integer -> Integer -> Evm (Maybe Operand)
binOp t instr left right = do
  op2 PUSH32 left
  op MLOAD
  op2 PUSH32 right
  op MLOAD
  op instr
  addr <- alloc (sizeof S.IntT)
  op2 PUSH32 addr
  op MSTORE
  return (Just (Operand t addr))
