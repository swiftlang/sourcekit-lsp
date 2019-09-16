import * as child_process from "child_process";
import * as fs from "fs";

export function exists(file: string): Promise<boolean> {
  return new Promise<boolean>((resolve, _reject) => {
    fs.exists(file, value => {
      resolve(value);
    });
  });
}

export function exec(command: string, options: child_process.ExecOptions): Promise<{ stdout: string; stderr: string }> {
  return new Promise<{ stdout: string; stderr: string }>((resolve, reject) => {
    child_process.exec(command, options, (error, stdout, stderr) => {
      if (error) {
        reject({ error, stdout, stderr });
      }
      resolve({ stdout, stderr });
    });
  });
}
