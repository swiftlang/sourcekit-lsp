import * as path from "path";
import * as vscode from "vscode";
import {
  SwiftPMTaskDefinition,
  SwiftPackageDescription,
  toSwiftPackageDescription,
  TargetType,
  SwiftPMTarget
} from "./taskInterfaces";

import { exec, exists } from "./utils";

export class SwiftPMTaskProvider implements vscode.TaskProvider {

  static taskType: string = "swift-package";
  private swiftpmPromise: Thenable<vscode.Task[]> | undefined = undefined;

  constructor(workspaceRoot: string) {
    let pattern = path.join(workspaceRoot, "Package.swift");
    let fileWatcher = vscode.workspace.createFileSystemWatcher(pattern);

    fileWatcher.onDidChange(() => (this.swiftpmPromise = undefined));
    fileWatcher.onDidCreate(() => (this.swiftpmPromise = undefined));
    fileWatcher.onDidDelete(() => (this.swiftpmPromise = undefined));
  }

  public provideTasks(): Thenable<vscode.Task[]> | undefined {
    if (!this.swiftpmPromise) {
      this.swiftpmPromise = getSwiftPMTasks();
    }
    return this.swiftpmPromise;
  }

  public resolveTask(_task: vscode.Task): vscode.Task | undefined {
    const task = _task.definition.task;
    // A Swift task consists of a task and an optional file as specified in SwiftTaskDefinition
    // Make sure that this looks like a SwiftPM task by checking that there is a task.
    if (task) {
      const definition: SwiftPMTaskDefinition = <any>_task.definition;
      return new vscode.Task(
        definition,
        definition.task,
        "swift",
        new vscode.ShellExecution(`swift ${definition.task}`)
      );
    }
    return undefined;
  }
}

let _channel: vscode.OutputChannel;

function getOutputChannel(): vscode.OutputChannel {

  if (!_channel) {
    _channel = vscode.window.createOutputChannel("SwiftPM Task Auto Detection");
  }
  return _channel;
}

async function getSwiftPMTasks(): Promise<vscode.Task[]> {

  let workspaceRoot = vscode.workspace.rootPath;
  let result: vscode.Task[] = [];
  if (!workspaceRoot) {
    return result;
  }

  let packageFile = path.join(workspaceRoot, "Package.swift");
  if (!(await exists(packageFile))) {
    return result;
  }

  let describePackage = "swift package describe --type json";
  try {

    let { stdout, stderr } = await exec(describePackage, {
      cwd: workspaceRoot
    });

    if (stderr && stderr.length > 0) {
      getOutputChannel().appendLine(stderr);
      getOutputChannel().show(true);
    }

    let result: vscode.Task[] = [];
    if (stdout) {
      let packageDescription: SwiftPackageDescription = toSwiftPackageDescription(
        stdout
      );

      result.push(getBuildTask([]));

      for (let target of packageDescription.targets) {
        if (target.type == TargetType.Executable) {
          result.push(getExecutableTask(target));
        }
      }

      if (packageDescription.targets.filter(target => target.type === TargetType.Test).length != 0) {
        result.push(getTestTask());
      }
    }
    return result;

  } catch (err) {
    let channel = getOutputChannel();
    if (err.stderr) {
      channel.appendLine(err.stderr);
    }
    if (err.stdout) {
      channel.appendLine(err.stdout);
    }
    channel.appendLine("Auto detecting Swift Package Tasks failed.");
    channel.show(true);
    return result;
  }
}

function getTestTask(): vscode.Task {
  let kind: SwiftPMTaskDefinition = {
    type: SwiftPMTaskProvider.taskType,
    task: "test",
    args: []
  };

  let taskName = `test`;
  let task = new vscode.Task(
    kind,
    taskName,
    "swift-package",
    new vscode.ShellExecution(`swift ${kind.task}`)
  );
  task.group = vscode.TaskGroup.Test;
  task.isBackground = false;
  return task;
}

function getExecutableTask(target: SwiftPMTarget): vscode.Task {
  let kind: SwiftPMTaskDefinition = {
    type: SwiftPMTaskProvider.taskType,
    task: "run",
    args: []
  };

  let taskName = `run ${target.name}`;
  let task = new vscode.Task(
    kind,
    taskName,
    "swift-package",
    new vscode.ShellExecution(`swift ${kind.task}`)
  );
  // task.group = vscode.TaskGroup.Build;
  task.isBackground = false;
  return task;
}

function getBuildTask(args: string[]): vscode.Task {
  let kind: SwiftPMTaskDefinition = {
    type: SwiftPMTaskProvider.taskType,
    task: "build",
    args: args //["debug", "release"]
  };

  var taskName = "build";
  let task = new vscode.Task(
    kind,
    taskName,
    "swift-package",
    // TODO: Build Arguments
    new vscode.ShellExecution(`swift ${kind.task}`)
  );
  task.group = vscode.TaskGroup.Build;
  task.isBackground = false;
  return task;
}
