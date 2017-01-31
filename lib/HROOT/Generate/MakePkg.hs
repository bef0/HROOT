{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}

-----------------------------------------------------------------------------
-- |
-- Module      : HROOT.Generate.MakePkg
-- Copyright   : (c) 2011-2017 Ian-Woo Kim
-- 
-- License     : GPL-3
-- Maintainer  : ianwookim@gmail.com
-- Stability   : experimental
-- Portability : GHC
--
-- Generate source code for HROOT  
--
-----------------------------------------------------------------------------

module HROOT.Generate.MakePkg where

import           Control.Applicative
import           Control.Monad
import           Data.List 
import qualified Data.Map                               as M
import           Data.Maybe
import           Data.Monoid                                   ( (<>) )
import           Data.Text                                     ( Text )
import           Distribution.Package
import           Distribution.PackageDescription        hiding ( exposedModules )
import           Distribution.PackageDescription.Parse
import           Distribution.Verbosity
import           Distribution.Version 
import           Language.Haskell.Exts.Pretty                  ( prettyPrint )
import           System.Console.CmdArgs
import           System.Directory
import           System.FilePath 
import           System.IO
-- 
import           FFICXX.Generate.Code.Cabal
import           FFICXX.Generate.Code.Cpp
import           FFICXX.Generate.Code.Dependency
import           FFICXX.Generate.Config
import           FFICXX.Generate.ContentMaker 
import           FFICXX.Generate.Builder
import           FFICXX.Generate.Type.Annotate
import           FFICXX.Generate.Type.Class
import           FFICXX.Generate.Type.Module                   ( ClassImportHeader(..), ClassModule(..)
                                                               , Namespace(..), TopLevelImportHeader(..)
                                                               , PackageConfig(..)
                                                               )
import           FFICXX.Generate.Type.PackageInterface
import           FFICXX.Generate.Util
-- 
import qualified Paths_HROOT_generate                   as H

data UmbrellaPackageConfig = UPkgCfg { upkgname :: String } 

data EachPackageConfig  = PkgCfg { pkgname :: String 
                                  , pkg_summarymodule :: String 
                                  , pkg_typemacro :: TypeMacro
                                  , pkg_classes :: [Class] 
                                  , pkg_cihs :: [ClassImportHeader]
                                  , pkg_tih :: TopLevelImportHeader
                                  , pkg_modules :: [ClassModule]
                                  , pkg_annotateMap :: AnnotateMap
                                  , pkg_deps :: [String]
                                  , pkg_hsbootlst :: [String]
                                  , pkg_synopsis :: String
                                  , pkg_description :: String
                                  } 

-- | 
copyPredefinedFiles :: String   -- ^ package name 
                    -> ([String],[String]) -- ^ files in root dir, directories
                    -> FilePath 
                    -> IO () 
copyPredefinedFiles pkgname (files,dirs) ibase = do 
    tmpldir <- H.getDataDir >>= return . (</> "template") 
    mapM_ (\x->copyFileWithMD5Check (tmpldir </> pkgname </> x) (ibase </> x)) files 
    forM_ dirs $ \dir -> do 
      notExistThenCreate (ibase </> dir) 
      b <- doesDirectoryExist (tmpldir </> pkgname </> dir) 
      when b $ do 
        contents <- getDirectoryContents (tmpldir </> pkgname </> dir)
        mapM_ (f (tmpldir </> pkgname </> dir) (ibase </> dir)) contents 
  where 
    f src dest s = if s /= "." && s /= ".."
                   then copyFileWithMD5Check (src</>s) (dest</>s) 
                   else return () 


-- | 
mkCROOTIncludeHeaders :: ([Namespace],String) -> Class -> ([Namespace],[HeaderName])
mkCROOTIncludeHeaders (nss,str) c = 
  case class_name c of
    "Deletable" -> (nss,[])
    "TROOT" -> (nss++[NS "ROOT"],[HdrName (str </> (class_name c) ++ ".h")])
    _ -> (nss,[HdrName (str </> (class_name c) ++ ".h")])

-- | 
mkCabalFile :: Bool  -- ^ is umbrella 
            -> FFICXXConfig 
            -> EachPackageConfig 
            -> Handle 
            -> IO () 
mkCabalFile isUmbrella config PkgCfg {..} h = do 
  version <- getHROOTVersion config
  let deps | null pkg_deps = [] 
           | otherwise = "," ++ intercalate "," pkg_deps 
  let str = subst cabalTemplate . context $
              [ ("pkgname", pkgname) 
              , ("version", version) 
              , ("synopsis", pkg_synopsis )
              , ("description", pkg_description )
              , ("homepage", "http://ianwookim.org/HROOT")
              , ("licenseField", "license: LGPL-2.1" ) 
              , ("licenseFileField", "license-file: LICENSE")
              , ("author", "Ian-Woo Kim")
              , ("maintainer", "Ian-Woo Kim <ianwookim@gmail.com>")
              , ("category", "Graphics, Statistics, Math, Numerical")
              , ("sourcerepository","")
              , ("buildtype", "Custom")
              , ("ccOptions", "-std=c++14")
              , ("deps", deps) 
              , ("csrcFiles", if isUmbrella then "" else genCsrcFiles (pkg_tih,pkg_modules))
              , ("includeFiles", let cihs = cmCIH =<< pkg_modules
                                 in if isUmbrella then "" else genIncludeFiles pkgname (cihs, []))
              , ("cppFiles", if isUmbrella then "" else genCppFiles (pkg_tih,pkg_modules))
              , ("exposedModules", genExposedModules pkg_summarymodule (pkg_modules,[])) 
              , ("otherModules", genOtherModules pkg_modules)
              , ("extralibdirs",  "" )  -- this need to be changed 
              , ("extraincludedirs", "" )  -- this need to be changed 
              , ("extraLibraries", "")
              , ("cabalIndentation", cabalIndentation)
              ]
  hPutStrLn h str

-- | 
getHROOTVersion :: FFICXXConfig -> IO String 
getHROOTVersion conf = do 
  let hrootgeneratecabal = fficxxconfig_scriptBaseDir conf </> "HROOT-generate.cabal"
  gdescs <- readPackageDescription normal hrootgeneratecabal
  let vnums = versionBranch . pkgVersion . package . packageDescription $ gdescs 
  return $ intercalate "." (map show vnums)

-- |
makePackage :: FFICXXConfig -> EachPackageConfig -> IO () 
makePackage config pkgcfg@(PkgCfg {..}) = do 
    let workingDir = fficxxconfig_workingDir config 
        ibase = fficxxconfig_installBaseDir config
        cabalFileName = pkgname <.> "cabal" 
    -- 
    putStrLn "======================" 
    putStrLn ("working on " ++ pkgname) 
    putStrLn "----------------------"
    putStrLn "cabal file generation" 
    notExistThenCreate ibase 
    notExistThenCreate workingDir 

    copyPredefinedFiles pkgname (["CHANGES","Config.hs","LICENSE","Setup.lhs"], ["src","csrc"])   ibase 

    withFile (workingDir </> cabalFileName) WriteMode $ 
      \h -> mkCabalFile False config pkgcfg h
    let cglobal = mkGlobal pkg_classes
    -- 
    putStrLn "header file generation"
    let gen :: FilePath -> String -> IO ()
        gen file str =
          let path = workingDir </> file in withFile path WriteMode (flip hPutStrLn str)

    
    gen (pkgname <> "Type.h") (buildTypeDeclHeader pkg_typemacro (map cihClass pkg_cihs))
    mapM_ (\hdr -> gen (unHdrName (cihSelfHeader hdr)) (buildDeclHeader pkg_typemacro pkgname hdr)) pkg_cihs
    gen (tihHeaderFileName pkg_tih <.> "h") (buildTopLevelFunctionHeader pkg_typemacro pkgname pkg_tih)
    -- 
    putStrLn "cpp file generation" 
    mapM_ (\hdr -> gen (cihSelfCpp hdr) (buildDefMain hdr)) pkg_cihs
    gen (tihHeaderFileName pkg_tih <.> "cpp") (buildTopLevelFunctionCppDef pkg_tih)
    -- 
    putStrLn "RawType.hs file generation" 
    mapM_ (\m -> gen (cmModule m <.> "RawType" <.> "hs") (prettyPrint (buildRawTypeHs m))) pkg_modules 
    -- 
    putStrLn "FFI.hsc file generation"
    mapM_ (\m -> gen (cmModule m <.> "FFI" <.> "hsc") (prettyPrint (buildFFIHsc m))) pkg_modules
    -- 
    putStrLn "Interface.hs file generation" 
    mapM_ (\m -> gen (cmModule m <.> "Interface" <.> "hs") (prettyPrint (buildInterfaceHs pkg_annotateMap m))) pkg_modules
    -- 
    putStrLn "Cast.hs file generation"
    mapM_ (\m -> gen (cmModule m <.> "Cast" <.> "hs") (prettyPrint (buildCastHs m))) pkg_modules
    -- 
    putStrLn "Implementation.hs file generation"
    mapM_ (\m -> gen (cmModule m <.> "Implementation" <.> "hs") (prettyPrint (buildImplementationHs pkg_annotateMap m))) pkg_modules
    -- 
    putStrLn "hs-boot file generation" 
    mapM_ (\m -> gen (m <.> "Interface" <.> "hs-boot") (prettyPrint (buildInterfaceHSBOOT m))) pkg_hsbootlst  
    -- 
    putStrLn "module file generation" 
    mapM_ (\m -> gen (cmModule m <.> "hs") (prettyPrint (buildModuleHs m))) pkg_modules
    -- 
    putStrLn "summary module generation generation"
    gen (pkg_summarymodule <.> "hs") (buildPkgHs pkg_summarymodule pkg_modules pkg_tih)
    -- 
    putStrLn "copying"
    copyFileWithMD5Check (workingDir </> cabalFileName)  (ibase </> cabalFileName) 
    copyCppFiles workingDir (csrcDir ibase) pkgname (PkgConfig pkg_modules pkg_cihs pkg_tih [] [])
    mapM_ (copyModule workingDir (srcDir ibase)) pkg_modules 
    moduleFileCopy workingDir (srcDir ibase) (pkg_summarymodule <.> "hs")
    
    -- 
    putStrLn "======================"

---------------------------------
-- for umbrella package 
---------------------------------

pkgHsTemplate :: Text
pkgHsTemplate =
  "module $summarymod (\n\
  \$exportList\n\
  \) where\n\
  \\n\
  \$importList\n\
  \\n\
  \$topLevelDef\n"

-- | make an umbrella package for this project
makeUmbrellaPackage :: FFICXXConfig -> EachPackageConfig -> [String] -> IO () 
makeUmbrellaPackage config pkgcfg@(PkgCfg {..}) mods = do 
    putStrLn "======================"
    putStrLn "Umbrella Package 'HROOT' generation"
    putStrLn "----------------------"

    let cabalFileName = pkgname <.> "cabal" 
        ibase = fficxxconfig_installBaseDir config 
        workingDir = fficxxconfig_workingDir config 
    putStrLn "cabal file generation"
    -- 
    notExistThenCreate ibase
    notExistThenCreate workingDir
    -- 
    copyPredefinedFiles pkgname 
      (["CHANGES","Config.hs","LICENSE","README.md","Setup.lhs"],["example","src","csrc"]) ibase 
    withFile (workingDir </> cabalFileName) WriteMode $ 
      \h -> mkCabalFile True config pkgcfg h

    putStrLn "umbrella module generation"
    withFile (workingDir </> pkg_summarymodule <.> "hs" )  WriteMode $ \h -> do 
      let exportListStr = intercalateWith (conn "\n, ") (\x->"module " ++ x ) mods 
          importListStr = intercalateWith connRet (\x->"import " ++ x) mods
          str = subst pkgHsTemplate . context $ 
                  [ ("summarymod", pkg_summarymodule)
                  , ("exportList", exportListStr) 
                  , ("importList", importListStr)
                  , ("topLevelDef", "")
                  ]
      hPutStrLn h str
    putStrLn "copying"
    copyFileWithMD5Check (workingDir </> cabalFileName)  (ibase </> cabalFileName) 
    copyFileWithMD5Check (workingDir </> pkg_summarymodule <.> "hs") (ibase </> "src" </> pkg_summarymodule <.> "hs")  

