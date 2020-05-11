import * as path from "path";
import * as child_process from "child_process";
import * as fs from "fs";

import {
  TaskProvider,
  Task,
  workspace,
  ShellExecution,
  OutputChannel,
  window,
  TaskGroup,
  TaskDefinition,
} from "vscode";
import {
  SwiftPMTaskDefinition,
  SwiftPackageDescription,
  TargetType,
  SwiftPMTarget,
} from "./interfaces";

export class SwiftPMTaskProvider implements TaskProvider {
  static taskType: string = "swift";
  private swiftpmPromise: Thenable<Task[]> | undefined = undefined;

  private _channel?: OutputChannel;

  constructor(workspaceRoot: string) {
    let pattern = path.join(workspaceRoot, "Package.swift");
    let fileWatcher = workspace.createFileSystemWatcher(pattern);

    fileWatcher.onDidChange(() => (this.swiftpmPromise = undefined));
    fileWatcher.onDidCreate(() => (this.swiftpmPromise = undefined));
    fileWatcher.onDidDelete(() => (this.swiftpmPromise = undefined));
  }

  public provideTasks(): Thenable<Task[]> | undefined {
    if (!this.swiftpmPromise) {
      this.swiftpmPromise = this.getSwiftPMTasks();
    }
    return this.swiftpmPromise;
  }

  public resolveTask(_task: Task): Task | undefined {
    const task = _task.definition.task;
    // A Swift task consists of a task and an optional file as specified in SwiftTaskDefinition
    // Make sure that this looks like a SwiftPM task by checking that there is a task.
    if (task) {
      const definition: SwiftPMTaskDefinition = <any>_task.definition;
      return new Task(
        definition,
        definition.task,
        "swift",
        new ShellExecution(`swift ${definition.task}`)
      );
    }
    return undefined;
  }

  // Helper Methods

  getOutputChannel(): OutputChannel {
    if (!this._channel) {
      this._channel = window.createOutputChannel("SwiftPM Task Auto Detection");
    }
    return this._channel;
  }

  async getSwiftPMTasks(): Promise<Task[]> {
    let workspaceRoot = workspace.rootPath;
    let result: Task[] = [];
    if (!workspaceRoot) {
      return result;
    }

    let packageFile = path.join(workspaceRoot, "Package.swift");
    if (!(await this.exists(packageFile))) {
      return result;
    }

    let describePackage = "swift package describe --type json";
    try {
      let { stdout, stderr } = await this.exec(describePackage, {
        cwd: workspaceRoot,
      });

      if (stderr && stderr.length > 0) {
        this.getOutputChannel().appendLine(stderr);
        this.getOutputChannel().show(true);
      }

      let result: Task[] = [];
      if (stdout) {
        let packageDescription: SwiftPackageDescription = JSON.parse(stdout);

        if (packageDescription.targets.map(item => item.type).includes(TargetType.Library)) {
          result.push(this.addBuildTask());
        }

        if (packageDescription.targets.map(item => item.type).includes(TargetType.Test)) {
          result.push(this.addTestTask());
        }

        result.push(this.addCleanTask());


        packageDescription.targets.forEach((target) => {
          switch (target.type) {
            case TargetType.Executable:
              result.push(this.addExecutableTask(target));
              break;
            case TargetType.Library:
              break;
            case TargetType.Test:
              result.push(this.addTestTask(target));
              break;
          }
        });

      

      }
      return result;
    } catch (err) {
      let channel = this.getOutputChannel();
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

  private addExecutableTask(target: SwiftPMTarget) {
    let kind: TaskDefinition = {
      type: SwiftPMTaskProvider.taskType,
      args: [],
    };
    let task = new Task(kind, `run ${target.name}`, "swift", new ShellExecution(`swift run ${target.name}`));
    task.group = TaskGroup.Build;
    task.isBackground = false;
    return task;
  }

  private addTestTask(target?: SwiftPMTarget) {
    let kind: TaskDefinition = {
      type: SwiftPMTaskProvider.taskType,
      args: [],
    };
    if (target) {
      let task = new Task(kind, `test ${target.name}`, "swift", new ShellExecution(`swift test --filter ${target.name}`));
      task.group = TaskGroup.Build;
      task.isBackground = false;
      return task;
    }else {
      let task = new Task(kind, `test`, "swift", new ShellExecution(`swift test`));
      task.group = TaskGroup.Build;
      task.isBackground = false;
      return task;
    }
   
  }

  private addBuildTask() {
    let kind: TaskDefinition = {
      type: SwiftPMTaskProvider.taskType,
      args: [],
    };
    let task = new Task(kind, `build`, "swift", new ShellExecution(`swift build`));
    task.group = TaskGroup.Build;
    task.isBackground = false;
    return task
  }

  private addCleanTask() {
    let kind: TaskDefinition = {
      type: SwiftPMTaskProvider.taskType,
      args: [],
    };
    let task = new Task(kind, `clean`, "swift", new ShellExecution(`swift package clean`));
    task.group = TaskGroup.Build;
    task.isBackground = false;
    return task
  }

  exists(file: string): Promise<boolean> {
    return new Promise<boolean>((resolve, _reject) => {
      fs.exists(file, (value) => {
        resolve(value);
      });
    });
  }

  exec(
    command: string,
    options: child_process.ExecOptions
  ): Promise<{ stdout: string; stderr: string }> {
    return new Promise<{ stdout: string; stderr: string }>(
      (resolve, reject) => {
        child_process.exec(command, options, (error, stdout, stderr) => {
          if (error) {
            reject({ error, stdout, stderr });
          }
          resolve({ stdout, stderr });
        });
      }
    );
  }
}
