import { readEnvFile } from './env.js';
import { logger } from './logger.js';

/**
 * Transcribe an audio buffer using an OpenAI-compatible Whisper endpoint.
 * Returns the transcript text on success, null on failure or if not configured.
 */
export async function transcribeAudio(
  audio: Buffer,
  filename: string,
): Promise<string | null> {
  const env = readEnvFile([
    'WHISPER_API_URL',
    'WHISPER_API_KEY',
    'WHISPER_MODEL',
  ]);
  const url = process.env.WHISPER_API_URL || env.WHISPER_API_URL;
  const apiKey = process.env.WHISPER_API_KEY || env.WHISPER_API_KEY;
  const model = process.env.WHISPER_MODEL || env.WHISPER_MODEL || 'whisper-1';

  if (!url || !apiKey) {
    logger.debug(
      'Whisper not configured (WHISPER_API_URL or WHISPER_API_KEY missing)',
    );
    return null;
  }

  try {
    const form = new FormData();
    form.append('file', new Blob([audio]), filename);
    form.append('model', model);

    const res = await fetch(url, {
      method: 'POST',
      headers: { Authorization: `Bearer ${apiKey}` },
      body: form,
    });

    if (!res.ok) {
      const body = await res.text().catch(() => '');
      logger.error(
        { status: res.status, body },
        'Whisper transcription request failed',
      );
      return null;
    }

    const data = (await res.json()) as { text?: string };
    const text = data.text?.trim();
    if (!text) {
      logger.warn('Whisper returned empty transcript');
      return null;
    }

    logger.info({ length: text.length, model }, 'Transcribed voice message');
    return text;
  } catch (err) {
    logger.error({ err }, 'Whisper transcription error');
    return null;
  }
}
