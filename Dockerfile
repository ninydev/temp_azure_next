# Этап 1: Установка зависимостей
FROM node:24-alpine AS deps
# Установка libc6-compat (требуется для некоторых зависимостей Next.js в Alpine)
RUN apk add --no-cache libc6-compat
WORKDIR /app

# Копируем файлы конфигурации пакетного менеджера
COPY package.json yarn.lock* package-lock.json* pnpm-lock.yaml* ./
RUN \
  if [ -f yarn.lock ]; then yarn --frozen-lockfile; \
  elif [ -f package-lock.json ]; then npm ci; \
  elif [ -f pnpm-lock.yaml ]; then corepack enable pnpm && pnpm i --frozen-lockfile; \
  else echo "Lockfile not found." && exit 1; \
  fi


# Этап 2: Сборка приложения
FROM node:24-alpine AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Отключаем телеметрию во время сборки
ENV NEXT_TELEMETRY_DISABLED 1

RUN yarn build


# Этап 3: Финальный образ (Runner)
FROM node:24-alpine AS runner
WORKDIR /app

ENV NODE_ENV production
ENV NEXT_TELEMETRY_DISABLED 1

RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs

# Копируем публичные файлы и статические ассеты
COPY --from=builder /app/public ./public

# Автоматически создаем папку .next и назначаем права пользователю nextjs
# Это важно для работы в App Service
RUN mkdir .next
RUN chown nextjs:nodejs .next

# Копируем результаты standalone сборки
# https://nextjs.org/docs/advanced-features/output-file-tracing
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

USER nextjs

EXPOSE 3000

ENV PORT 3000
# Переменная окружения для хоста, важна для Docker контейнеров
ENV HOSTNAME "0.0.0.0"

# Запускаем сервер, который был сгенерирован Next.js в standalone моде
CMD ["node", "server.js"]
