-- | Types and classes related to configuration when the server is initialised
module Hasura.Server.Init.Config
  ( -- * HGEOptions
    HGEOptionsRaw (..),
    horDatabaseUrl,
    horMetadataDbUrl,
    horCommand,

    -- * HGEOptionsRaw
    HGEOptions (..),
    hoCommand,

    -- * PostgresConnInfo
    PostgresConnInfo (..),
    pciDatabaseConn,
    pciRetries,

    -- * PostgresRawConnInfo
    PostgresConnInfoRaw (..),
    _PGConnDatabaseUrl,
    _PGConnDetails,
    mkUrlConnInfo,

    -- * PostgresRawConnDetails
    PostgresConnDetailsRaw (..),

    -- * HGECommand
    HGECommand (..),
    _HCServe,

    -- * ServeOptionsRaw
    ServeOptionsRaw (..),
    API (..),
    KeepAliveDelay (..),
    OptionalInterval (..),
    AuthHookRaw,
    ConnParamsRaw (..),
    ResponseInternalErrorsConfig (..),
    WSConnectionInitTimeout (..),
    defaultKeepAliveDelay,
    defaultWSConnectionInitTimeout,
    msToOptionalInterval,
    rawConnDetailsToUrl,
    rawConnDetailsToUrlText,
    shouldIncludeInternal,

    -- * ServeOptions
    ServeOptions (..),

    -- * Downgrade Options
    DowngradeOptions (..),
  )
where

--------------------------------------------------------------------------------

import Control.Lens (Lens', Prism')
import Control.Lens qualified as Lens
import Data.Aeson (FromJSON, ToJSON)
import Data.Aeson qualified as Aeson
import Data.Text qualified as Text
import Data.Time qualified as Time
import Data.URL.Template qualified as Template
import Database.PG.Query qualified as Q
import Hasura.GraphQL.Execute.Subscription.Options qualified as Subscription.Options
import Hasura.GraphQL.Schema.NamingCase (NamingCase)
import Hasura.GraphQL.Schema.Options qualified as Options
import Hasura.Logging qualified as Logging
import Hasura.Prelude
import Hasura.RQL.Types.Common qualified as Common
import Hasura.Server.Auth qualified as Auth
import Hasura.Server.Cors qualified as Cors
import Hasura.Server.Logging qualified as Server.Logging
import Hasura.Server.Types qualified as Types
import Hasura.Session qualified as Session
import Network.Wai.Handler.Warp qualified as Warp
import Network.WebSockets qualified as WebSockets

--------------------------------------------------------------------------------

-- | Raw HGE Options from the arg parser and the env.
data HGEOptionsRaw impl = HGEOptionsRaw
  { _horDatabaseUrl :: PostgresConnInfo (Maybe PostgresConnInfoRaw),
    _horMetadataDbUrl :: Maybe String,
    _horCommand :: HGECommand impl
  }

horDatabaseUrl :: Lens' (HGEOptionsRaw impl) (PostgresConnInfo (Maybe PostgresConnInfoRaw))
horDatabaseUrl = Lens.lens _horDatabaseUrl $ \hdu a -> hdu {_horDatabaseUrl = a}

horMetadataDbUrl :: Lens' (HGEOptionsRaw impl) (Maybe String)
horMetadataDbUrl = Lens.lens _horMetadataDbUrl $ \hdu a -> hdu {_horMetadataDbUrl = a}

horCommand :: Lens' (HGEOptionsRaw impl) (HGECommand impl)
horCommand = Lens.lens _horCommand $ \hdu a -> hdu {_horCommand = a}

--------------------------------------------------------------------------------

-- | The final processed HGE options.
data HGEOptions impl = HGEOptions
  { _hoDatabaseUrl :: PostgresConnInfo (Maybe Common.UrlConf),
    _hoMetadataDbUrl :: Maybe String,
    _hoCommand :: HGECommand impl
  }

hoCommand :: Lens' (HGEOptions impl) (HGECommand impl)
hoCommand = Lens.lens _hoCommand $ \hdu a -> hdu {_hoCommand = a}

--------------------------------------------------------------------------------

-- | Postgres connection info tupled with a retry count.
--
-- In practice, the @a@ here is one of the following:
-- 1. 'Maybe PostgresConnInfoRaw'
-- 2. 'Maybe UrlConf'
-- 3. 'Maybe Text'
-- 4. 'Maybe DatabaseUrl' where 'DatabaseUrl' is an alias for 'Text'
--
-- If it contains a 'Maybe PostgresConnInfoRaw' then you have not yet
-- processed your arg parser results.
data PostgresConnInfo a = PostgresConnInfo
  { _pciDatabaseConn :: a,
    _pciRetries :: Maybe Int
  }
  deriving (Show, Eq, Functor, Foldable, Traversable)

pciDatabaseConn :: Lens' (PostgresConnInfo a) a
pciDatabaseConn = Lens.lens _pciDatabaseConn $ \pci a -> pci {_pciDatabaseConn = a}

pciRetries :: Lens' (PostgresConnInfo a) (Maybe Int)
pciRetries = Lens.lens _pciRetries $ \pci mi -> pci {_pciRetries = mi}

--------------------------------------------------------------------------------

-- | Postgres Connection info can come in the form of a templated URI
-- string or structured data.
data PostgresConnInfoRaw
  = PGConnDatabaseUrl Template.URLTemplate
  | PGConnDetails PostgresConnDetailsRaw
  deriving (Show, Eq)

mkUrlConnInfo :: String -> PostgresConnInfoRaw
mkUrlConnInfo = PGConnDatabaseUrl . Template.mkPlainURLTemplate . Text.pack

_PGConnDatabaseUrl :: Prism' PostgresConnInfoRaw Template.URLTemplate
_PGConnDatabaseUrl = Lens.prism' PGConnDatabaseUrl $ \case
  PGConnDatabaseUrl template -> Just template
  PGConnDetails _ -> Nothing

_PGConnDetails :: Prism' PostgresConnInfoRaw PostgresConnDetailsRaw
_PGConnDetails = Lens.prism' PGConnDetails $ \case
  PGConnDatabaseUrl _ -> Nothing
  PGConnDetails prcd -> Just prcd

rawConnDetailsToUrl :: PostgresConnDetailsRaw -> Template.URLTemplate
rawConnDetailsToUrl =
  Template.mkPlainURLTemplate . rawConnDetailsToUrlText

--------------------------------------------------------------------------------

-- | Structured Postgres connection information as provided by the arg
-- parser or env vars.
data PostgresConnDetailsRaw = PostgresConnDetailsRaw
  { connHost :: String,
    connPort :: Int,
    connUser :: String,
    connPassword :: String,
    connDatabase :: String,
    connOptions :: Maybe String
  }
  deriving (Eq, Read, Show)

instance FromJSON PostgresConnDetailsRaw where
  parseJSON = Aeson.withObject "PostgresConnDetailsRaw" \o -> do
    connHost <- o Aeson..: "host"
    connPort <- o Aeson..: "port"
    connUser <- o Aeson..: "user"
    connPassword <- o Aeson..: "password"
    connDatabase <- o Aeson..: "database"
    connOptions <- o Aeson..:? "options"
    pure $ PostgresConnDetailsRaw {..}

instance ToJSON PostgresConnDetailsRaw where
  toJSON PostgresConnDetailsRaw {..} =
    Aeson.object $
      [ "host" Aeson..= connHost,
        "port" Aeson..= connPort,
        "user" Aeson..= connUser,
        "password" Aeson..= connPassword,
        "database" Aeson..= connDatabase
      ]
        <> catMaybes [fmap ("options" Aeson..=) connOptions]

rawConnDetailsToUrlText :: PostgresConnDetailsRaw -> Text
rawConnDetailsToUrlText PostgresConnDetailsRaw {..} =
  Text.pack $
    "postgresql://" <> connUser
      <> ":"
      <> connPassword
      <> "@"
      <> connHost
      <> ":"
      <> show connPort
      <> "/"
      <> connDatabase
      <> maybe "" ("?options=" <>) connOptions

--------------------------------------------------------------------------------

-- | The HGE Arg parser Command choices.
--
-- This is polymorphic so that we can pack either 'ServeOptionsRaw' or
-- 'ProServeOptionsRaw' in it.
data HGECommand a
  = HCServe a
  | HCExport
  | HCClean
  | HCVersion
  | HCDowngrade !DowngradeOptions
  deriving (Show, Eq)

_HCServe :: Prism' (HGECommand a) a
_HCServe = Lens.prism' HCServe \case
  HCServe a -> Just a
  _ -> Nothing

--------------------------------------------------------------------------------

-- | The Serve Command options accumulated from the arg parser and env.
data ServeOptionsRaw impl = ServeOptionsRaw
  { rsoPort :: Maybe Int,
    rsoHost :: Maybe Warp.HostPreference,
    rsoConnParams :: ConnParamsRaw,
    rsoTxIso :: Maybe Q.TxIsolation,
    rsoAdminSecret :: Maybe Auth.AdminSecretHash,
    rsoAuthHook :: AuthHookRaw,
    rsoJwtSecret :: Maybe Auth.JWTConfig,
    rsoUnAuthRole :: Maybe Session.RoleName,
    rsoCorsConfig :: Maybe Cors.CorsConfig,
    rsoEnableConsole :: Bool,
    rsoConsoleAssetsDir :: Maybe Text,
    rsoEnableTelemetry :: Maybe Bool,
    rsoWsReadCookie :: Bool,
    rsoStringifyNum :: Options.StringifyNumbers,
    rsoDangerousBooleanCollapse :: Maybe Bool,
    rsoEnabledAPIs :: Maybe [API],
    rsoMxRefetchInt :: Maybe Subscription.Options.RefetchInterval,
    rsoMxBatchSize :: Maybe Subscription.Options.BatchSize,
    -- We have different config options for livequery and streaming subscriptions
    rsoStreamingMxRefetchInt :: Maybe Subscription.Options.RefetchInterval,
    rsoStreamingMxBatchSize :: Maybe Subscription.Options.BatchSize,
    rsoEnableAllowlist :: Bool,
    rsoEnabledLogTypes :: Maybe [Logging.EngineLogType impl],
    rsoLogLevel :: Maybe Logging.LogLevel,
    rsoDevMode :: Bool,
    rsoAdminInternalErrors :: Maybe Bool,
    rsoEventsHttpPoolSize :: Maybe Int,
    rsoEventsFetchInterval :: Maybe Milliseconds,
    rsoAsyncActionsFetchInterval :: Maybe OptionalInterval,
    rsoEnableRemoteSchemaPermissions :: Options.RemoteSchemaPermissions,
    rsoWebSocketCompression :: Bool,
    rsoWebSocketKeepAlive :: Maybe KeepAliveDelay,
    rsoInferFunctionPermissions :: Maybe Options.InferFunctionPermissions,
    rsoEnableMaintenanceMode :: Types.MaintenanceMode (),
    rsoSchemaPollInterval :: Maybe OptionalInterval,
    -- See Note [Experimental features] at bottom of module
    rsoExperimentalFeatures :: Maybe [Types.ExperimentalFeature],
    rsoEventsFetchBatchSize :: Maybe Common.NonNegativeInt,
    rsoGracefulShutdownTimeout :: Maybe Seconds,
    rsoWebSocketConnectionInitTimeout :: Maybe WSConnectionInitTimeout,
    rsoEnableMetadataQueryLoggingEnv :: Server.Logging.MetadataQueryLoggingMode,
    -- | stores global default naming convention
    rsoDefaultNamingConvention :: Maybe NamingCase
  }

data API
  = METADATA
  | GRAPHQL
  | PGDUMP
  | DEVELOPER
  | CONFIG
  | METRICS
  deriving (Show, Eq, Read, Generic)

instance FromJSON API where
  parseJSON = Aeson.withText "API" \case
    "metadata" -> pure METADATA
    "graphql" -> pure GRAPHQL
    "pgdump" -> pure PGDUMP
    "developer" -> pure DEVELOPER
    "config" -> pure CONFIG
    "metrics" -> pure METRICS
    x -> fail $ "unexpected string '" <> show x <> "'."

instance ToJSON API where
  toJSON = \case
    METADATA -> Aeson.String "metadata"
    GRAPHQL -> Aeson.String "graphql"
    PGDUMP -> Aeson.String "pgdump"
    DEVELOPER -> Aeson.String "developer"
    CONFIG -> Aeson.String "config"
    METRICS -> Aeson.String "metrics"

instance Hashable API

-- TODO(SOLOMON): Monomorphize
type AuthHookRaw = Auth.AuthHookG (Maybe Text) (Maybe Auth.AuthHookType)

-- | Sleep time interval for recurring activities such as (@'asyncActionsProcessor')
--   Presently @'msToOptionalInterval' interprets `0` as Skip.
data OptionalInterval
  = -- | No polling
    Skip
  | -- | Interval time
    Interval !Milliseconds
  deriving (Show, Eq)

msToOptionalInterval :: Milliseconds -> OptionalInterval
msToOptionalInterval = \case
  0 -> Skip
  s -> Interval s

instance FromJSON OptionalInterval where
  parseJSON v = msToOptionalInterval <$> Aeson.parseJSON v

instance ToJSON OptionalInterval where
  toJSON = \case
    Skip -> Aeson.toJSON @Milliseconds 0
    Interval s -> Aeson.toJSON s

-- | The Raw configuration data from the Arg and Env parsers needed to
-- construct a 'Q.ConnParams'
data ConnParamsRaw = ConnParamsRaw
  { rcpStripes :: Maybe Int,
    rcpConns :: Maybe Int,
    rcpIdleTime :: Maybe Int,
    -- | Time from connection creation after which to destroy a connection and
    -- choose a different/new one.
    rcpConnLifetime :: Maybe Time.NominalDiffTime,
    rcpAllowPrepare :: Maybe Bool,
    -- | See @HASURA_GRAPHQL_PG_POOL_TIMEOUT@
    rcpPoolTimeout :: Maybe Time.NominalDiffTime
  }
  deriving (Show, Eq)

newtype KeepAliveDelay = KeepAliveDelay {unKeepAliveDelay :: Seconds}
  deriving (Eq, Show)

instance FromJSON KeepAliveDelay where
  parseJSON = Aeson.withObject "KeepAliveDelay" \o -> do
    unKeepAliveDelay <- o Aeson..: "keep_alive_delay"
    pure $ KeepAliveDelay {..}

instance ToJSON KeepAliveDelay where
  toJSON KeepAliveDelay {..} =
    Aeson.object ["keep_alive_delay" Aeson..= unKeepAliveDelay]

defaultKeepAliveDelay :: KeepAliveDelay
defaultKeepAliveDelay = KeepAliveDelay $ fromIntegral (5 :: Int)

newtype WSConnectionInitTimeout = WSConnectionInitTimeout {unWSConnectionInitTimeout :: Seconds}
  deriving (Eq, Show)

instance FromJSON WSConnectionInitTimeout where
  parseJSON = Aeson.withObject "WSConnectionInitTimeout" \o -> do
    unWSConnectionInitTimeout <- o Aeson..: "w_s_connection_init_timeout"
    pure $ WSConnectionInitTimeout {..}

instance ToJSON WSConnectionInitTimeout where
  toJSON WSConnectionInitTimeout {..} =
    Aeson.object ["w_s_connection_init_timeout" Aeson..= unWSConnectionInitTimeout]

defaultWSConnectionInitTimeout :: WSConnectionInitTimeout
defaultWSConnectionInitTimeout = WSConnectionInitTimeout $ fromIntegral (3 :: Int)

--------------------------------------------------------------------------------

-- | The final Serve Command options accummulated from the Arg Parser
-- and the Environment, fully processed and ready to apply when
-- running the server.
data ServeOptions impl = ServeOptions
  { soPort :: Int,
    soHost :: Warp.HostPreference,
    soConnParams :: Q.ConnParams,
    soTxIso :: Q.TxIsolation,
    soAdminSecret :: HashSet Auth.AdminSecretHash,
    soAuthHook :: Maybe Auth.AuthHook,
    soJwtSecret :: [Auth.JWTConfig],
    soUnAuthRole :: Maybe Session.RoleName,
    soCorsConfig :: Cors.CorsConfig,
    soEnableConsole :: Bool,
    soConsoleAssetsDir :: Maybe Text,
    soEnableTelemetry :: Bool,
    soStringifyNum :: Options.StringifyNumbers,
    soDangerousBooleanCollapse :: Bool,
    soEnabledAPIs :: HashSet API,
    soLiveQueryOpts :: Subscription.Options.LiveQueriesOptions,
    soStreamingQueryOpts :: Subscription.Options.StreamQueriesOptions,
    soEnableAllowlist :: Bool,
    soEnabledLogTypes :: HashSet (Logging.EngineLogType impl),
    soLogLevel :: Logging.LogLevel,
    soResponseInternalErrorsConfig :: ResponseInternalErrorsConfig,
    soEventsHttpPoolSize :: Maybe Int,
    soEventsFetchInterval :: Maybe Milliseconds,
    soAsyncActionsFetchInterval :: OptionalInterval,
    soEnableRemoteSchemaPermissions :: Options.RemoteSchemaPermissions,
    soConnectionOptions :: WebSockets.ConnectionOptions,
    soWebSocketKeepAlive :: KeepAliveDelay,
    soInferFunctionPermissions :: Options.InferFunctionPermissions,
    soEnableMaintenanceMode :: Types.MaintenanceMode (),
    soSchemaPollInterval :: OptionalInterval,
    soExperimentalFeatures :: HashSet Types.ExperimentalFeature,
    soEventsFetchBatchSize :: Common.NonNegativeInt,
    soDevMode :: Bool,
    soGracefulShutdownTimeout :: Seconds,
    soWebSocketConnectionInitTimeout :: WSConnectionInitTimeout,
    soEventingMode :: Types.EventingMode,
    soReadOnlyMode :: Types.ReadOnlyMode,
    soEnableMetadataQueryLogging :: Server.Logging.MetadataQueryLoggingMode,
    soDefaultNamingConvention :: Maybe NamingCase
  }

-- | @'ResponseInternalErrorsConfig' represents the encoding of the internal
-- errors in the response to the client.
-- See the github comment https://github.com/hasura/graphql-engine/issues/4031#issuecomment-609747705 for more details.
data ResponseInternalErrorsConfig
  = InternalErrorsAllRequests
  | InternalErrorsAdminOnly
  | InternalErrorsDisabled
  deriving (Show, Eq)

shouldIncludeInternal :: Session.RoleName -> ResponseInternalErrorsConfig -> Bool
shouldIncludeInternal role = \case
  InternalErrorsAllRequests -> True
  InternalErrorsAdminOnly -> role == Session.adminRoleName
  InternalErrorsDisabled -> False

--------------------------------------------------------------------------------

-- | The Downgrade Command options. These are only sourced from the
-- Arg Parser and are used directly in 'Hasura.Server.Migrate'.
data DowngradeOptions = DowngradeOptions
  { dgoTargetVersion :: !Text,
    dgoDryRun :: !Bool
  }
  deriving (Show, Eq)

--------------------------------------------------------------------------------

{- Note: [Experimental features]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

The graphql-engine accepts a list of experimental features that can be
enabled at the startup. Experimental features are a way to introduce
new, but not stable features to our users in a manner in which they have
the choice to enable or disable a certain feature(s).

The objective of an experimental feature should be that when the feature is disabled,
the graphql-engine should work the same way as it worked before adding the said feature.

The experimental feature's flag is `--experimental-features` and the corresponding
environment variable is `HASURA_GRAPHQL_EXPERIMENTAL_FEATURES` which expects a comma-seperated
value.

When an experimental feature is stable enough i.e. it's stable through multiple non-beta releases
then we make the feature not experimental i.e. it will always be enabled. Note that when we do this
we still have to support parsing of the experimental feature because users of the previous version
will have it enabled and when they upgrade an error should not be thrown at the startup. For example:

The inherited roles was an experimental feature when introduced and it was enabled by
setting `--experimental-features` to `inherited_roles` and then it was decided to make the inherited roles
a stable feature, so it was removed as an experimental feature but the code was modified such that
`--experimental-features inherited_roles` to not throw an error.

-}
