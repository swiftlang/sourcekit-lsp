'use strict';
import * as vscode from 'vscode';
import * as langclient from 'vscode-languageclient/node';
import { InlayHint, InlayHintsParams, inlayHintsRequest } from './lspExtensions';

// The implementation is loosely based on the rust-analyzer implementation
// of inlay hints: https://github.com/rust-analyzer/rust-analyzer/blob/master/editors/code/src/inlay_hints.ts

// Note that once support for inlay hints is officially added to LSP/VSCode,
// this module providing custom decorations will no longer be needed!

export async function activateInlayHints(
    context: vscode.ExtensionContext,
    client: langclient.LanguageClient
): Promise<void> {
    let updater: HintsUpdater | null = null;

    const onConfigChange = async () => {
        const config = vscode.workspace.getConfiguration('sourcekit-lsp');
        const wasEnabled = updater !== null;
        const isEnabled = config.get<boolean>('inlayHints.enabled', false);

        if (wasEnabled !== isEnabled) {
            updater?.dispose();
            if (isEnabled) {
                updater = new HintsUpdater(client);
            } else {
                updater = null;
            }
        }
    };

    context.subscriptions.push(vscode.workspace.onDidChangeConfiguration(onConfigChange));
    context.subscriptions.push({ dispose: () => updater?.dispose() });

    onConfigChange().catch(console.error);
}

interface InlayHintStyle {
    decorationType: vscode.TextEditorDecorationType;

    makeDecoration(hint: InlayHint, converter: langclient.Protocol2CodeConverter): vscode.DecorationOptions;
}

const hintStyle: InlayHintStyle = {
    decorationType: vscode.window.createTextEditorDecorationType({
        after: {
            color: new vscode.ThemeColor('editorCodeLens.foreground'),
            fontStyle: 'normal',
            fontWeight: 'normal'
        }
    }),

    makeDecoration: (hint, converter) => ({
        range: converter.asRange({
            start: { ...hint.position, character: hint.position.character - 1 },
            end: hint.position
        }),
        renderOptions: {
            after: {
                // U+200C is a zero-width non-joiner to prevent the editor from
                // forming a ligature between the code and an inlay hint.
                contentText: `\u{200c}: ${hint.label}`
            }
        }
    })
};

interface SourceFile {
    /** Source of the token for cancelling in-flight inlay hint requests. */
    inFlightInlayHints: null | vscode.CancellationTokenSource;

    /** Most recently applied decorations. */
    cachedDecorations: null | vscode.DecorationOptions[];

    /** The source file document in question. */
    document: vscode.TextDocument;
}

class HintsUpdater implements vscode.Disposable {
    private readonly disposables: vscode.Disposable[] = [];
    private sourceFiles: Map<string, SourceFile> = new Map(); // uri -> SourceFile

    constructor(private readonly client: langclient.LanguageClient) {
        // Register listeners
        vscode.window.onDidChangeVisibleTextEditors(this.onDidChangeVisibleTextEditors, this, this.disposables);
        vscode.workspace.onDidChangeTextDocument(this.onDidChangeTextDocument, this, this.disposables);

        // Set up initial cache
        this.visibleSourceKitLSPEditors.forEach(editor => this.sourceFiles.set(
            editor.document.uri.toString(),
            {
                document: editor.document,
                inFlightInlayHints: null,
                cachedDecorations: null
            }
        ));

        this.syncCacheAndRenderHints();
    }

    private onDidChangeVisibleTextEditors(): void {
        const newSourceFiles = new Map<string, SourceFile>();

        // Rerender all, even up-to-date editors for simplicity
        this.visibleSourceKitLSPEditors.forEach(async editor => {
            const uri = editor.document.uri.toString();
            const file = this.sourceFiles.get(uri) ?? {
                document: editor.document,
                inFlightInlayHints: null,
                cachedDecorations: null
            };
            newSourceFiles.set(uri, file);

            // No text documents changed, so we may try to use the cache
            if (!file.cachedDecorations) {
                const hints = await this.fetchHints(file);
                file.cachedDecorations = this.hintsToDecorations(hints);
            }

            this.renderDecorations(editor, file.cachedDecorations);
        });

        // Cancel requests for no longer visible (disposed) source files
        this.sourceFiles.forEach((file, uri) => {
            if (!newSourceFiles.has(uri)) {
                file.inFlightInlayHints?.cancel();
            }
        });

        this.sourceFiles = newSourceFiles;
    }

    private onDidChangeTextDocument(event: vscode.TextDocumentChangeEvent): void {
        if (event.contentChanges.length !== 0 && this.isSourceKitLSPDocument(event.document)) {
            this.syncCacheAndRenderHints();
        }
    }

    private syncCacheAndRenderHints(): void {
        this.sourceFiles.forEach(async (file, uri) => {
            const hints = await this.fetchHints(file);

            const decorations = this.hintsToDecorations(hints);
            file.cachedDecorations = decorations;

            this.visibleSourceKitLSPEditors.forEach(editor => {
                if (editor.document.uri.toString() === uri) {
                    this.renderDecorations(editor, decorations);
                }
            });
        });
    }

    private get visibleSourceKitLSPEditors(): vscode.TextEditor[] {
        return vscode.window.visibleTextEditors.filter(e => this.isSourceKitLSPDocument(e.document));
    }

    private isSourceKitLSPDocument(document: vscode.TextDocument): boolean {
        // TODO: Add other SourceKit-LSP languages if/once we forward inlay
        // hint requests to clangd.
        return document.languageId === 'swift' && document.uri.scheme === 'file';
    }

    private renderDecorations(editor: vscode.TextEditor, decorations: vscode.DecorationOptions[]): void {
        editor.setDecorations(hintStyle.decorationType, decorations);
    }

    private hintsToDecorations(hints: InlayHint[]): vscode.DecorationOptions[] {
        const converter = this.client.protocol2CodeConverter;
        return hints.map(h => hintStyle.makeDecoration(h, converter));
    }

    private async fetchHints(file: SourceFile): Promise<InlayHint[]> {
        file.inFlightInlayHints?.cancel();

        const tokenSource = new vscode.CancellationTokenSource();
        file.inFlightInlayHints = tokenSource;

        // TODO: Specify a range
        const params: InlayHintsParams = {
            textDocument: { uri: file.document.uri.toString() }
        }

        try {
            return await this.client.sendRequest(inlayHintsRequest, params, tokenSource.token);
        } catch (e) {
            this.client.outputChannel.appendLine(`Could not fetch inlay hints: ${e}`);
            return [];
        } finally {
            if (file.inFlightInlayHints.token === tokenSource.token) {
                file.inFlightInlayHints = null;
            }
        }
    }

    dispose(): void {
        this.sourceFiles.forEach(file => file.inFlightInlayHints?.cancel());
        this.visibleSourceKitLSPEditors.forEach(editor => this.renderDecorations(editor, []));
        this.disposables.forEach(d => d.dispose());
    }
}
