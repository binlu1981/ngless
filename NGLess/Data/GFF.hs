{-# LANGUAGE OverloadedStrings #-}

module Data.GFF
    ( GffLine(..)
    , GffType(..)
    , GffStrand(..)
    , gffGeneId
    , readAnnotations
    , readLine
    , parseGffAttributes
    , checkAttrTag
    , trimString
    , filterFeatures
    , showType
    ) where


import Control.DeepSeq

import qualified Data.ByteString as S
import qualified Data.ByteString.Lazy as L
import qualified Data.ByteString.Char8 as S8
import qualified Data.ByteString.Lazy.Char8 as L8

import Data.Maybe

import Language

data GffType = GffExon
                | GffGene
                | GffCDS
                | GffOther S.ByteString
            deriving (Eq, Show)

data GffStrand = GffPosStrand | GffNegStrand | GffUnknownStrand | GffUnStranded
            deriving (Eq, Show, Enum)


data GffLine = GffLine
            { gffSeqId :: S.ByteString
            , gffSource :: S.ByteString
            , gffType :: GffType
            , gffStart :: Int
            , gffEnd :: Int
            , gffScore :: Maybe Float
            , gffString :: GffStrand
            , gffPhase :: Int -- ^phase: use -1 to denote .
            , gffAttributes :: S.ByteString
            } deriving (Eq,Show)


parseGffAttributes :: S.ByteString -> [(S.ByteString, S.ByteString)]
parseGffAttributes = map (\(aid,aval) -> (aid, S.tail aval))
                        . map (\x -> S8.break (== (checkAttrTag x)) x)
                        . map trimString
                        . S8.split ';'
                        . S.init -- remove last ';'

--Check if the atribution tag is '=' or ' '
checkAttrTag :: S.ByteString -> Char
checkAttrTag s = case S8.elemIndex '=' s of
    Nothing -> ' '
    _       -> '='

-- remove ' ' from begining and end.
trimString :: S.ByteString -> S.ByteString
trimString = trimBeg . trimEnd
    where
        trimBeg x = if isSpace $ S8.index x 0 -- first element
                        then S8.tail x
                        else x
        trimEnd x = if isSpace $ S8.last x -- last element 
                        then S8.init x
                        else x

isSpace :: Char -> Bool
isSpace = (== ' ')

instance NFData GffLine where
    rnf gl = (gffSeqId gl) `seq`
            (gffSource gl) `seq`
            (gffType gl) `seq`
            (gffStart gl) `seq`
            (gffEnd gl) `seq`
            (gffScore gl) `deepseq`
            (gffString gl) `seq`
            (gffPhase gl) `seq`
            (gffAttributes gl) `seq`
            ()

gffGeneId g = do
    let attrs = (parseGffAttributes $ gffAttributes g)
        res = lookup (S8.pack "ID") attrs
        res' = lookup (S8.pack "gene_id") attrs
    case res of
        Nothing -> res'
        _ -> res

readAnnotations :: L.ByteString -> [GffLine]
readAnnotations = readAnnotations' . L8.lines

readAnnotations' :: [L.ByteString] -> [GffLine]
readAnnotations' [] = []
readAnnotations' (l:ls) = case L8.head l of
                '#' -> readAnnotations' ls
                '>' -> []
                _ -> (readLine l:readAnnotations' ls)

readLine :: L.ByteString -> GffLine
readLine line = if length tokens == 9
            then GffLine
                (strict tk0)
                (strict tk1)
                (parsegffType $ strict tk2)
                (read $ L8.unpack tk3)
                (read $ L8.unpack tk4)
                (score tk5)
                (strand $ L8.head tk6)
                (phase tk7)
                (strict tk8)
            else error (concat ["unexpected line in GFF: ", show line])
    where
        tokens = L8.split '\t' line
        [tk0,tk1,tk2,tk3,tk4,tk5,tk6,tk7,tk8] = tokens
        parsegffType "exon" = GffExon
        parsegffType "gene" = GffGene
        parsegffType "CDS" = GffCDS
        parsegffType t = GffOther t
        score "." = Nothing
        score v = Just (read $ L8.unpack v)
        strand '.' = GffUnStranded
        strand '+' = GffPosStrand
        strand '-' = GffNegStrand
        strand '?' = GffUnknownStrand
        strand _ = error "unhandled value for strand"
        phase "." = -1
        phase r = read (L8.unpack r)


strict :: L.ByteString -> S.ByteString
strict = S.concat . L.toChunks

filterFeatures :: Maybe NGLessObject -> GffLine -> Bool
filterFeatures feats gffL = maybe True (fFeat gffL) feats
  where 
        fFeat g (NGOList f) = foldl (\a b -> a || b) False (map (filterFeatures' g) f)
        fFeat _ err = error("Type should be NGOList but received: " ++ (show err))

filterFeatures' :: GffLine -> NGLessObject -> Bool
filterFeatures' g (NGOSymbol "gene") = (==GffGene) . gffType $ g
filterFeatures' g (NGOSymbol "exon") = (==GffExon) . gffType $ g
filterFeatures' g (NGOSymbol "cds" ) = (==GffCDS) . gffType  $ g
filterFeatures' g f = error ("not yet implemented feature" ++ (show g) ++ " " ++ (show f))


showType :: GffType -> S.ByteString
showType GffExon = "exon"
showType GffGene = "gene"
showType GffCDS = "CDS"