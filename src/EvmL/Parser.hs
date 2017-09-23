{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings     #-}

module EvmL.Parser where

--------------------------------------------------------------------------------
import           Control.Arrow      ((>>>))
import           Data.Functor
import qualified Data.Text          as T
import qualified EvmL.Lexer         as Lexer
import           Text.Parsec        as P
import           Text.Parsec.String (Parser)
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

data Expr =
    If Expr Expr
  | PrimBool Bool
  | PrimInt Integer
  deriving Show

text :: Stream s m Char => T.Text -> ParsecT s u m T.Text
text input = T.pack <$> string (T.unpack input)

if' :: Parser Expr
if' = do
  text "if"
  many space
  pred' <- expr
  many space
  text "then"
  many space
  body <- expr
  return (If pred' body)

bool :: Parser Expr
bool = try (text "true" $> PrimBool True)
   <|> try (text "false" $> PrimBool False)
   <?> "a boolean value"

int :: Parser Expr
int = PrimInt <$> Lexer.integer

prims :: Parser Expr
prims = try bool
    <|> try int
    <?> "a primitive"

expr :: Parser Expr
expr = if'
   <|> prims
   <?> "an expression"

parse :: T.Text -> Either ParseError Expr
parse = T.unpack >>> P.parse expr "<unknown>"
