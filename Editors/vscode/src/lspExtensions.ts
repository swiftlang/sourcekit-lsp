'use strict';
import * as langclient from 'vscode-languageclient/node';

// Definitions for non-standard requests used by sourcekit-lsp

export interface InlayHintsParams {
    /**
     * The text document.
     */
    textDocument: langclient.TextDocumentIdentifier;

    /**
     * If set, the reange for which inlay hints are
     * requested. If unset, hints for the entire document
     * are returned.
     */
    range?: langclient.Range;

    /**
     * The categories of inlay hints that are requested.
     * If unset, all categories are returned.
     */
    only?: string[];
}

export interface InlayHint {
    /**
     * The position within the code that this hint is
     * attached to.
     */
    position: langclient.Position;

    /**
     * The hint's kind, used for more flexible client-side
     * styling of the hint.
     */
    category?: string;

    /**
     * The hint's rendered label.
     */
    label: string;
}

export const inlayHintsRequest = new langclient.RequestType<InlayHintsParams, InlayHint[], unknown>('sourcekit-lsp/inlayHints');
