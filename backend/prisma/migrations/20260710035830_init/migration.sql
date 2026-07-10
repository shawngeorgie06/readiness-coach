-- CreateTable
CREATE TABLE "User" (
    "id" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "goal" TEXT NOT NULL DEFAULT 'recomp',
    "sleepNeedHours" DOUBLE PRECISION NOT NULL DEFAULT 8,
    "settings" JSONB,

    CONSTRAINT "User_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "HealthSample" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "hkUuid" TEXT NOT NULL,
    "type" TEXT NOT NULL,
    "startAt" TIMESTAMP(3) NOT NULL,
    "endAt" TIMESTAMP(3) NOT NULL,
    "value" DOUBLE PRECISION,
    "unit" TEXT,
    "metadata" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "HealthSample_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Workout" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "hkUuid" TEXT NOT NULL,
    "sport" TEXT NOT NULL,
    "startAt" TIMESTAMP(3) NOT NULL,
    "endAt" TIMESTAMP(3) NOT NULL,
    "durationMin" DOUBLE PRECISION NOT NULL,
    "avgHrBpm" DOUBLE PRECISION,
    "calories" DOUBLE PRECISION,
    "strain" DOUBLE PRECISION NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Workout_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "DailyScore" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "date" DATE NOT NULL,
    "sleepScore" INTEGER NOT NULL,
    "recoveryScore" INTEGER NOT NULL,
    "loadScore" INTEGER NOT NULL,
    "readiness" INTEGER NOT NULL,
    "decision" TEXT NOT NULL,
    "overrides" JSONB NOT NULL,
    "calibrating" BOOLEAN NOT NULL,
    "drivers" JSONB NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "DailyScore_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "AdvisorNote" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "date" DATE NOT NULL,
    "decision" TEXT NOT NULL,
    "noteJson" JSONB NOT NULL,
    "source" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AdvisorNote_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "HealthSample_userId_type_startAt_idx" ON "HealthSample"("userId", "type", "startAt");

-- CreateIndex
CREATE UNIQUE INDEX "HealthSample_userId_hkUuid_key" ON "HealthSample"("userId", "hkUuid");

-- CreateIndex
CREATE INDEX "Workout_userId_startAt_idx" ON "Workout"("userId", "startAt");

-- CreateIndex
CREATE UNIQUE INDEX "Workout_userId_hkUuid_key" ON "Workout"("userId", "hkUuid");

-- CreateIndex
CREATE UNIQUE INDEX "DailyScore_userId_date_key" ON "DailyScore"("userId", "date");

-- CreateIndex
CREATE UNIQUE INDEX "AdvisorNote_userId_date_key" ON "AdvisorNote"("userId", "date");

-- AddForeignKey
ALTER TABLE "HealthSample" ADD CONSTRAINT "HealthSample_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Workout" ADD CONSTRAINT "Workout_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "DailyScore" ADD CONSTRAINT "DailyScore_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "AdvisorNote" ADD CONSTRAINT "AdvisorNote_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
