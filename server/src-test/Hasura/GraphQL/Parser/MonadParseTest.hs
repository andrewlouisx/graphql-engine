module Hasura.GraphQL.Parser.MonadParseTest (spec) where

import Data.Aeson.Internal
import Hasura.Base.ErrorMessage
import Hasura.GraphQL.Parser.Class.Parse
import Hasura.GraphQL.Parser.ErrorCode
import Hasura.GraphQL.Parser.Monad
import Hasura.GraphQL.Parser.TestInstances ()
import Hasura.Prelude
import Test.Hspec

runParse' :: Parse () -> Either ParseError ()
runParse' = runParse @_ @()

errorMessage :: ErrorMessage
errorMessage = "oh no"

spec :: Spec
spec = do
  describe "parse error path" $ do
    it "is empty when no keys added" $ do
      let parser = parseError errorMessage
          expected = ParseError {pePath = [], peMessage = errorMessage, peCode = ValidationFailed}
      runParse' parser `shouldBe` Left expected

    it "has two items in the order they were added" $ do
      let parser = withKey (Key "dog") (withKey (Key "log") (parseError errorMessage))
          expected = ParseError {pePath = [Key "dog", Key "log"], peMessage = errorMessage, peCode = ValidationFailed}
      runParse' parser `shouldBe` Left expected

    it "has multiple keys provisioned from a JSONPath" $ do
      let path :: JSONPath = [Key "hi", Index 1, Key "foo bar"]
          parser = withPath path (withKey (Key "first") (parseError errorMessage))
          expected = ParseError {pePath = Key "first" : path, peMessage = errorMessage, peCode = ValidationFailed}
      runParse' parser `shouldBe` Left expected
