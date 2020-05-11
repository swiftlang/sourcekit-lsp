import { TaskDefinition } from "vscode";

export enum ModuleType {
  ClangTarget = "ClangTarget",
  SwiftTarget = "SwiftTarget",
}

export enum TargetType {
  Executable = "executable",
  Library = "library",
  Test = "test",
}

export interface SwiftPMTarget {
  c99name: string;
  module_type: ModuleType;
  name: string;
  path: string;
  sources: string[];
  type: TargetType;
}

export interface SwiftPackageDescription {
  name: string;
  path: string;
  targets: SwiftPMTarget[];
}

export interface SwiftPMTaskDefinition extends TaskDefinition {
  task: string;
  args: string[];
}
