import * as vscode from "vscode";

export interface SwiftPMTaskDefinition extends vscode.TaskDefinition {
  task: string;
  args: string[];
}

export interface SwiftPackageDescription {
  name: string;
  path: string;
  targets: SwiftPMTarget[];
}

export interface SwiftPMTarget {
  c99name: string;
  module_type: ModuleType;
  name: string;
  path: string;
  sources: string[];
  type: TargetType;
}

export enum ModuleType {
  ClangTarget = "ClangTarget",
  SwiftTarget = "SwiftTarget"
}

export enum TargetType {
  Executable = "executable",
  Library = "library",
  Test = "test"
}

export function toSwiftPackageDescription(
  json: string
): SwiftPackageDescription {
  return JSON.parse(json);
}
