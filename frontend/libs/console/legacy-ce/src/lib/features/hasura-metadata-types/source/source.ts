import { Driver } from '../../../dataSources';
import {
  BigQueryConfiguration,
  CitusConfiguration,
  MssqlConfiguration,
  PostgresConfiguration,
} from './configuration';
import { MetadataTable } from './table';
import { LogicalModel } from './logicalModel';
import { NativeQuery } from './nativeQuery';

export type NativeDrivers =
  | 'postgres'
  | 'alloy'
  | 'mssql'
  | 'mysql'
  | 'bigquery'
  | 'citus'
  | 'cockroach';

export type SuperConnectorDrivers =
  | 'snowflake'
  | 'athena'
  | 'mysqlgdc'
  | string;

export type SupportedDrivers = Driver | SuperConnectorDrivers;

export type NamingConvention = 'hasura-default' | 'graphql-default';

export type SourceCustomization = {
  root_fields?: {
    namespace?: string;
    prefix?: string;
    suffix?: string;
  };
  type_names?: {
    prefix?: string;
    suffix?: string;
  };
  naming_convention?: NamingConvention;
};

export type MetadataFunction = {
  function: QualifiedFunction;
  configuration?: {
    custom_name?: string;
    custom_root_fields?: {
      function?: string;
      function_aggregate?: string;
    };
    session_argument?: string;
    exposed_as?: 'mutation' | 'query';
  };
};

export type Source = {
  name: string;
  tables: MetadataTable[];
  customization?: SourceCustomization;
  functions?: MetadataFunction[];
  logical_models?: LogicalModel[];
  native_queries?: NativeQuery[];
} & (
  | {
      kind: 'postgres';
      configuration: PostgresConfiguration;
    }
  | {
      kind: 'mssql';
      configuration: MssqlConfiguration;
    }
  | {
      kind: 'bigquery';
      configuration: BigQueryConfiguration;
    }
  | {
      kind: 'citus';
      configuration: CitusConfiguration;
    }
  | {
      /**
       * This will still return string. This is implemented for readability reasons.
       * Until TS has negated types, any string will be considered as gdc
       */
      kind: Exclude<SupportedDrivers, NativeDrivers>;
      configuration: unknown;
      logical_models?: never;
      native_queries?: never;
    }
);

export type QualifiedFunction = unknown;
export type { LogicalModel, LogicalModelField } from './logicalModel';
export type { NativeQuery, NativeQueryArgument } from './nativeQuery';

export type BulkKeepGoingResponse = [
  | {
      message: 'success';
    }
  | {
      code: string;
      error: string;
      path: string;
    }
];
