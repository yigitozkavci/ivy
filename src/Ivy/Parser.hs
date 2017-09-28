{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings     #-}

module Ivy.Parser where

--------------------------------------------------------------------------------
import           Control.Arrow         ((>>>))
import           Data.Functor
import           Data.Functor.Identity
import qualified Data.Text             as T
import           Text.Parsec           as P
import           Text.Parsec.Char      as PC
import           Text.Parsec.Expr
import           Text.Parsec.String    (Parser)
--------------------------------------------------------------------------------
import           Ivy.Lexer
import           Ivy.Syntax
--------------------------------------------------------------------------------

text :: Stream s m Char => T.Text -> ParsecT s u m T.Text
text input = T.pack <$> string (T.unpack input)

prims :: Parser Expr
prims = (PrimInt <$> integer)
    <?> "primitive"

term :: Parser Integer
term = natural

binary s opType = Infix (reservedOp s >> return (BinaryOp opType))

binops = [ [ binary "*" OpMul AssocLeft
           , binary "/" OpDiv AssocLeft
           ]
         , [ binary "+" OpAdd AssocLeft
           , binary "-" OpSub AssocLeft
           ]
         ]

expr :: Parser Expr
expr = buildExpressionParser binops factor

typeDecl :: Parser Type
typeDecl =
  reserved "int" $> IntT

varDecl :: Parser Expr
varDecl = do
  type' <- typeDecl
  whitespace
  name <- identifier
  return $ VarDecl type' name
  <?> "variable decleration"

block :: Parser Block
block = Block <$> topLevel

timesIterationBegin :: Parser Expr
timesIterationBegin = do
  until <- integer
  symbol "."
  reserved "times"
  reserved "do"
  body <- block
  reserved "endtimes"
  return (Times until body)
  <?> "times iteration"

assignment :: Parser Expr
assignment = do
  name <- identifier
  whitespace
  reserved "="
  whitespace
  val <- expr
  return (Assignment name val)
  <?> "assignment"

factor :: Parser Expr
factor = try (parens expr <?> "parens")
     <|> try timesIterationBegin
     <|> try prims
     <|> try assignment
     <|> try varDecl
     <|> (Identifier <$> identifier <?> "identifier")
     <?>  "factor"

topLevel :: Parser [Expr]
topLevel = do
  many (expr <* reserved ";")
  <?> "topLevel"

parse :: T.Text -> Either ParseError Expr
parse = T.unpack >>> P.parse expr "<unknown>"

parseTopLevel :: T.Text -> Either ParseError [Expr]
parseTopLevel = T.unpack >>> P.parse topLevel "<unknown>"
