const peakPercents: Partial<Record<number, number>> = { 7: 15, 8: 24, 9: 8, 16: 6, 17: 17, 18: 18, 19: 7 };

export const peakDayShape: readonly number[] = Array.from({ length: 24 }, (_, parisHour) => (peakPercents[parisHour] ?? 5 / 17) / 100);
