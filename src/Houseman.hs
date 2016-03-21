{-# LANGUAGE NamedFieldPuns      #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Houseman where

import           Control.Concurrent
import           Data.List
import           System.Directory
import           System.Environment
import           System.Exit
import           System.Posix.Signals
import           System.Process

import qualified Configuration.Dotenv as Dotenv

import           Houseman.Internal    (bracketMany, runInPseudoTerminal,
                                       terminateAll, terminateAndWaitForProcess,
                                       watchTerminationOfProcesses)
import           Houseman.Logger      (newLogger, outputLog, runLogger)
import           Procfile.Types

run :: String -> Procfile -> IO ()
run cmd' apps = case find (\App{cmd} -> cmd == cmd') apps of
                  Just app -> Houseman.start [app] -- TODO Remove color in run command
                  Nothing   -> die ("Command '" ++ cmd' ++ "' not found in Procfile")

start :: [App] -> IO ()
start apps = do
    print apps
    logger <- newLogger
    bracketMany (map (`runApp` logger) apps) terminateAndWaitForProcess $ \phs -> do
      m <- newEmptyMVar

      _ <- installHandler keyboardSignal (Catch (terminateAll m phs)) Nothing

      -- If an app was terminated, terminate others as well
      _ <- forkIO $ watchTerminationOfProcesses (terminateAll m phs) phs
      _ <- forkIO $ outputLog logger

      exitStatus <- takeMVar m
      putStrLn "bye"
      exitWith exitStatus

-- Run given app with given logger.
runApp :: App -> Logger -> IO ProcessHandle
runApp App {name,cmd,args,envs} logger =  do
    currentEnvs <- getEnvironment
    d <- doesFileExist ".env"
    dotEnvs <- if d then Dotenv.parseFile ".env" else return []
    (master, _, ph) <- runInPseudoTerminal (proc cmd args) { env = Just (nub $ envs ++ dotEnvs ++ currentEnvs)}
    _ <- forkIO $ runLogger name logger master
    return ph
