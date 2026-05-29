type Primitive = string | number | boolean | null | undefined;

type DeepReadonly<T> =
  T extends Primitive ? T :
  T extends (...args: any[]) => any ? T :
  T extends readonly (infer U)[] ? ReadonlyArray<DeepReadonly<U>> :
  T extends object ? { readonly [K in keyof T]: DeepReadonly<T[K]> } :
  T;

type Flatten<T> = T extends Array<infer U> ? U extends Array<infer V> ? V : U : T;

type EventMap = {
  click: MouseEvent;
  hover: PointerEvent;
  scroll: Event;
};

type EventName<T extends string> = `on:${T}`;
type AllEvents = EventName<keyof EventMap & string>;

function parse(input: string): unknown;
function parse(input: string, strict: true): Record<string, unknown>;
function parse(input: string, strict?: boolean) {
  if (strict === true) {
    return JSON.parse(input);
  }
  try {
    return JSON.parse(input);
  } catch {
    return null;
  }
}

type UnwrapPromise<T> = T extends Promise<infer U> ? U : T;

async function wrap<T>(value: T): Promise<UnwrapPromise<T extends Promise<any> ? T : Promise<T>>> {
  return value as any;
}

type Flags<T> = {
  [K in keyof T as `is${Capitalize<string & K>}`]: boolean;
};

type Tuple = [number, string, ...boolean[]];

function tupleTest(...args: Tuple) {
  const [n, s, ...rest] = args;
  return s + n + rest.length;
}

type Json =
  | string
  | number
  | boolean
  | null
  | { [k: string]: Json }
  | Json[];

function getValue<T extends boolean>(flag: T): T extends true ? string : number {
  return (flag ? "yes" : 0) as any;
}

function labeledTest(input: number) {
  outer: for (let i = 0; i < 10; i++) {
    inner: for (let j = 0; j < 10; j++) {
      if (input === i + j) break outer;
      if (j > 5) continue inner;
    }
  }
  return input;
}

const tricky = 1 << 2 + 3;
const mixed = 10 / 2 * 3 - 4 + 1;

function Log(target: any, key: string, descriptor: PropertyDescriptor) {
  const original = descriptor.value;

  descriptor.value = function (...args: any[]) {
    return original.apply(this, args);
  };

  return descriptor;
}

class Service {
  private store: Map<string, unknown> = new Map();

  @Log
  setValue<T>(key: string, value: T): void {
    this.store.set(key, value);
  }

  @Log
  getValue<T>(key: string): T | undefined {
    return this.store.get(key) as T | undefined;
  }
}

namespace API {
  export type User = {
    id: number;
    name: string;
  };

  export function createUser(name: string): User {
    return { id: Math.random(), name };
  }
}

type A = { a: string; shared: number };
type B = { b: number; shared: string };

type C = A & B;

type WeirdUnion = A | B;

const key = "dynamic_key";

const obj = {
  [key]: 123,
  ["computed" + "_key"]: "value",
} as const;

type Infinite<T> = {
  value: T;
  next: Infinite<T>;
};

type Fn = <T, K extends keyof T>(obj: T, key: K) => T[K];

const fn: Fn = (obj, key) => obj[key];

async function* stream(limit: number) {
  let i = 0;
  while (i < limit) {
    yield i++;
  }
}

type Response = [status: number, message: string, data?: unknown];

const res: Response = [200, "OK", { ok: true }];

export { Service, API, parse, wrap };