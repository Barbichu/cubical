module Main where

import Control.Monad.Trans
import Control.Monad.Trans.State
import Control.Monad.Trans.Reader
import Control.Monad.Identity
import Control.Monad.Error
import Data.List
import System.Environment
import System.Console.Haskeline
import System.Directory

import Exp.Lex
import Exp.Par
import Exp.Print
import Exp.Abs
import Exp.Layout
import Exp.ErrM
import AbsToInternal
import Concrete
import qualified MTT as A
import qualified Eval as E

type Interpreter a = InputT IO a

defaultPrompt :: String
defaultPrompt = "> "

lexer :: String -> [Token]
lexer = resolveLayout True . myLexer

showTree :: (Show a, Print a) => a -> IO ()
showTree tree = do
  putStrLn $ "\n[Abstract Syntax]\n\n" ++ show tree
  putStrLn $ "\n[Linearized tree]\n\n" ++ printTree tree

main :: IO ()
main = getArgs >>= runInputT defaultSettings . runInterpreter

-- (not ok,loaded,already loaded defs) -> to load  -> (newnotok, newloaded, newdefs)
imports :: ([String],[String],[Def])  -> String-> Interpreter ([String],[String],[Def])
imports st@(notok,loaded,defs) f
  | f `elem` notok  = fail ("Looping imports in " ++ f)
  | f `elem` loaded = return st
  | otherwise       = do
    s <- lift $ readFile f
    let ts = lexer s
    case pModule ts of
      Bad s  -> fail $ "Parse Failed in file " ++ show f ++ "\n" ++ show s
      Ok mod@(Module _ imps defs') -> do
        let imps' = [ unIdent s ++ ".cub" | Import s <- imps ]
        (notok1,loaded1,def1) <- foldM imports (f:notok,loaded,defs) imps'
        outputStrLn $ "Parsed file " ++ show f ++ " successfully!"
        return (notok,f:loaded1,def1 ++ defs')

runInterpreter :: [FilePath] -> Interpreter ()
runInterpreter fs = case fs of
  [f] -> do
    -- parse and type-check files
    (_,_,defs) <- imports ([],[],[]) f
    -- Compute all constructors
    let cs = concat [ [ unIdent n | Sum n _ <- lbls] | DefData _ _ lbls <- defs ]
    let res = runResolver (local (insertConstrs cs) (resolveDefs defs))
    case res of
      Left err    -> outputStrLn $ "Resolver failed: " ++ err
      Right adefs -> case A.runDefs A.lEmpty adefs of
        Left err   -> outputStrLn $ "Type checking failed: " ++ err
        Right lenv -> do
          outputStrLn "File loaded."
          loop cs lenv
  _   -> do outputStrLn $ "Exactly one file expected: " ++ show fs
            loop [] A.lEmpty
  where
    loop :: [String] -> A.LEnv -> Interpreter ()
    loop cs lenv@(_,rho,_) = do
      input <- getInputLine defaultPrompt
      case input of
        Nothing    -> outputStrLn help >> loop cs lenv
        Just ":q"  -> return ()
        Just ":r"  -> runInterpreter fs
        Just (':':'l':' ':str) -> runInterpreter (words str)
        Just (':':'c':'d':' ':str) -> lift (setCurrentDirectory str) >> loop cs lenv
        Just ":h"  -> outputStrLn help >> loop cs lenv
        Just str   -> let ts = lexer str in
          case pExp ts of
            Bad err -> outputStrLn ("Parse error: " ++ err) >> loop cs lenv
            Ok exp  ->
              case runResolver (local (const (Env cs)) (resolveExp exp)) of
                Left err   -> outputStrLn ("Resolver failed: " ++ err) >> loop cs lenv
                Right body ->
                  case A.runInfer lenv body of
                    Left err -> outputStrLn ("Could not type-check: " ++ err) >> loop cs lenv
                    Right _  ->
                      case translate (A.defs rho body) of
                        Left err -> outputStrLn ("Could not translate to internal syntax: " ++ err) >>
                                    loop cs lenv
                        Right t  -> let value = E.eval E.Empty t in
                          outputStrLn ("EVAL: " ++ E.showVal value) >> loop cs lenv

help :: String
help = "\nAvailable commands:\n" ++
       "  <statement>     infer type and evaluate statement\n" ++
       "  :q              quit\n" ++
       "  :l <filename>   loads filename (and resets environment before)\n" ++
       "  :cd <path>      change directory to path\n" ++
       "  :r              reload\n" ++
       "  :h              display this message\n"
