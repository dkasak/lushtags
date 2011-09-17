----------------------------------------------------------------------------
-- |
-- Module      :  Tags
-- License     :  MIT (see LICENSE)
-- Authors     :  Bit Connor <bit@mutantlemon.com>
--
-- Maintainer  :  Bit Connor <bit@mutantlemon.com>
-- Stability   :  unstable
-- Portability :  portable
--
-- Extract Tags from a Haskell Module
--
-----------------------------------------------------------------------------

module Tags
    (
      Tag(..)
    , createTags
    , tagToString
    ) where

import Data.Vector(Vector, (!))
import Language.Haskell.Exts.Annotated (SrcSpan(..), SrcSpanInfo(..))
import Language.Haskell.Exts.Annotated.Syntax
import Language.Haskell.Exts.Pretty (prettyPrintStyleMode, Style(..), Mode(OneLineMode), defaultMode)

data Tag = Tag
    { tagName :: String
    , tagFile :: String
    , tagPattern :: String
    , tagKind :: TagKind
    , tagLine :: Int
    , tagParent :: Maybe (TagKind, String)
    , tagSignature :: Maybe String
    , tagAccess :: Maybe TagAccess
    }
    deriving (Eq, Ord, Show)

data TagKind
    = TModule
    | TImport
    | TType
    | TData
    | TNewType
    | TConstructor
    | TFunction
    deriving (Eq, Ord, Show)

-- Access modifiers comes from the C++ world. Haskell doesn't have them, but
-- they are useful for marking our tags with similar meanings. For example,
-- marking all exported functions as public, or marking qualified imports
-- differently from unqualified ones.
data TagAccess
    = AccessPublic
    | AccessPrivate
    | AccessProtected
    deriving (Eq, Ord, Show)

-- First letter of each kind name must be unique!
tagKindName :: TagKind -> String
tagKindName TModule = "module"
tagKindName TImport = "import"
tagKindName TType = "type"
tagKindName TData = "data"
tagKindName TNewType = "newtype"
tagKindName TConstructor = "constructor"
tagKindName TFunction = "function"

tagKindLetter :: TagKind -> Char
tagKindLetter = head . tagKindName

tagToString :: Tag -> String
tagToString tag =
    let parentStr = case tagParent tag of
            Nothing -> ""
            Just (kind, name) -> "\t" ++ tagKindName kind ++ ":" ++ name
        signatureStr = case tagSignature tag of
            Nothing -> ""
            Just sig -> "\tsignature:("++ sig ++ ")"
        accessStr = case tagAccess tag of
            Nothing -> ""
            Just AccessPublic -> "\taccess:public"
            Just AccessPrivate -> "\taccess:private"
            Just AccessProtected -> "\taccess:protected"
    in tagName tag ++ "\t" ++
            tagFile tag ++ "\t" ++
            tagPattern tag ++ ";\"\t" ++
            tagKindLetter (tagKind tag) : "\t" ++
            "line:" ++ show (tagLine tag) ++
            parentStr ++
            signatureStr ++
            accessStr

type FileLines = Vector String
type TagC = FileLines -> Tag

createTags :: (Module SrcSpanInfo, FileLines) -> [Tag]
createTags (Module _ mbHead _ imports decls, fileLines) =
    let moduleTag = case mbHead of
            Just (ModuleHead _ (ModuleName loc name) _ _) ->
                [tagC $ createTag name TModule Nothing Nothing Nothing loc]
            Nothing -> []
        importTags = map (tagC . createImportTag) imports
        declsTags = map tagC (concatMap createDeclTags decls)
    in moduleTag ++ importTags ++ declsTags
    where
        tagC :: TagC -> Tag
        tagC = ($ fileLines)
createTags _ = error "TODO Module is XmlPage/XmlHybrid (!)"

createTag :: String -> TagKind -> Maybe (TagKind, String) -> Maybe String -> Maybe TagAccess -> SrcSpanInfo -> TagC
createTag name kind parent signature access (SrcSpanInfo (SrcSpan file line _ _ _) _) fileLines = Tag
    { tagName = name
    , tagFile = file
    -- TODO This probably needs to be escaped:
    , tagPattern = "/^" ++ (fileLines ! (line - 1)) ++ "$/"
    , tagKind = kind
    , tagLine = line
    , tagParent = parent
    , tagSignature = signature
    , tagAccess = access
    }

createImportTag :: ImportDecl SrcSpanInfo -> TagC
createImportTag (ImportDecl loc (ModuleName _ name) qualified _ _ mbAlias mbSpecs) =
    let signature = case mbAlias of
            Nothing -> Nothing
            Just (ModuleName _ alias) -> Just alias
        access = case mbSpecs of
            Just (ImportSpecList _ False _) ->
                if qualified then Just AccessProtected else Nothing
            Just (ImportSpecList _ True _) ->
                -- imported names are excluded by 'hiding'
                if qualified then Just AccessProtected else Just AccessPrivate
            Nothing -> if qualified then Just AccessProtected else Just AccessPublic
    in createTag name TImport Nothing signature access loc

createDeclTags :: Decl SrcSpanInfo -> [TagC]
createDeclTags (TypeDecl _ hd _) =
    let (name, loc) = extractDeclHead hd
    in [createTag name TType Nothing Nothing Nothing loc]
createDeclTags (DataDecl _ dataOrNew _ hd constructors _) =
    let (name, loc) = extractDeclHead hd
        kind = case dataOrNew of
            DataType _ -> TData
            NewType _ -> TNewType
        dataTag = createTag name kind Nothing Nothing Nothing loc
    in dataTag : map (createConstructorTag (kind, name)) constructors
createDeclTags (TypeSig _ names t) =
    map createFunctionTag names
    where
        sig = prettyPrintStyleMode (Style OneLineMode 0 0) defaultMode t
        createFunctionTag :: Name SrcSpanInfo -> TagC
        createFunctionTag name =
            let (n, loc) = extractName name
            in createTag n TFunction Nothing (Just sig) Nothing loc
createDeclTags _ = []

-- TODO Also create tags for record fields
createConstructorTag :: (TagKind, String) -> QualConDecl SrcSpanInfo -> TagC
createConstructorTag parent (QualConDecl _ _ _ con) =
    let (name, loc) = extractConDecl con
    in createTag name TConstructor (Just parent) Nothing Nothing loc

extractDeclHead :: DeclHead SrcSpanInfo -> (String, SrcSpanInfo)
extractDeclHead (DHead _ name _) = extractName name
extractDeclHead (DHInfix _ _ name _) = extractName name
extractDeclHead (DHParen _ hd') = extractDeclHead hd'

extractConDecl :: ConDecl SrcSpanInfo -> (String, SrcSpanInfo)
extractConDecl (ConDecl _ name _) = extractName name
extractConDecl (InfixConDecl _ _ name _) = extractName name
extractConDecl (RecDecl _ name _) = extractName name

extractName :: Name SrcSpanInfo -> (String, SrcSpanInfo)
extractName (Ident loc name) = (name, loc)
extractName (Symbol loc name) = (name, loc)
