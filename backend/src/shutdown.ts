export interface ShutdownDependencies {
  closeServer: () => Promise<void>;
  disconnectDatabase: () => Promise<void>;
  onError: (error: unknown) => void;
}

export function createGracefulShutdown({
  closeServer,
  disconnectDatabase,
  onError,
}: ShutdownDependencies): () => Promise<void> {
  let shutdownPromise: Promise<void> | undefined;

  return () => {
    shutdownPromise ??= (async () => {
      try {
        await closeServer();
        await disconnectDatabase();
      } catch (error) {
        onError(error);
        throw error;
      }
    })();

    return shutdownPromise;
  };
}
