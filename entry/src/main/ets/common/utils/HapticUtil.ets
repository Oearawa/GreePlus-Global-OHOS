import { vibrator } from '@kit.SensorServiceKit';

/**
 * Tactile feedback helper using HarmonyOS native linear motor presets.
 * Fails silently on emulators or devices without a vibrator motor.
 */
export class HapticUtil {
  static tick(): void {
    try {
      vibrator.startVibration(
        {
          type: 'preset',
          effectId: 'haptic.clock.timer',
          count: 1
        },
        {
          usage: 'touch'
        }
      ).catch(() => {});
    } catch {
    }
  }
}
