declare namespace Pako {
    export interface Options {
        windowBits?: number;
        raw?: boolean;
        to?: 'string';
    }

    export type Data = Uint8Array | Array<number> | string;

    export function inflate(data: Data, options: Options & { to: 'string' }): string;
    export function inflate(data: Data, options?: Options): Uint8Array;

    export function inflateRaw(data: Data, options: Options & { to: 'string' }): string;
    export function inflateRaw(data: Data, options?: Options): Uint8Array;

    export function ungzip(data: Data, options: Options & { to: 'string' }): string;
    export function ungzip(data: Data, options?: Options): Uint8Array;

    export class Inflate {
        constructor(options?: Options);

        err: number;
        msg: string;
        result: Data;

        onData(chunk: Data): void;

        onEnd(status: number): void;

        push(data: Data | ArrayBuffer, mode?: number | boolean): boolean;
    }
}

export default Pako;