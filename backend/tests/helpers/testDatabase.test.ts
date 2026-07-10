import { describe, expect, it } from "vitest";
import { requireSafeTestDatabaseUrl } from "./testDatabase.js";

describe("requireSafeTestDatabaseUrl", () => {
  it("accepts a PostgreSQL database whose name ends in _test", () => {
    const value =
      "postgresql://postgres:postgres@127.0.0.1:5432/readiness_coach_test";

    expect(requireSafeTestDatabaseUrl(value)).toBe(value);
  });

  it("rejects a missing URL", () => {
    expect(() => requireSafeTestDatabaseUrl(undefined)).toThrow(
      "TEST_DATABASE_URL is required",
    );
  });

  it("rejects a non-test database", () => {
    expect(() =>
      requireSafeTestDatabaseUrl(
        "postgresql://postgres:postgres@127.0.0.1:5432/readiness_coach",
      ),
    ).toThrow('must end with "_test"');
  });

  it("rejects a non-PostgreSQL URL", () => {
    expect(() =>
      requireSafeTestDatabaseUrl("https://example.com/readiness_coach_test"),
    ).toThrow("must use PostgreSQL");
  });
});
