/** All assistant dates use Asia/Shanghai, independent of the device time zone. */
export function parseCampusDate(text: string): number | null {
  if (text.trim().length === 0) { return null; }
  const match = text.trim().match(/^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2})$/);
  if (match === null) { throw new Error('时间格式应为 YYYY-MM-DD HH:mm（北京时间）'); }
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const hour = Number(match[4]);
  const minute = Number(match[5]);
  const date = new Date(Date.UTC(year, month - 1, day, hour, minute));
  if (year < 2000 || year > 2100 || date.getUTCFullYear() !== year ||
    date.getUTCMonth() !== month - 1 || date.getUTCDate() !== day ||
    date.getUTCHours() !== hour || date.getUTCMinutes() !== minute) {
    throw new Error('日期或时间不存在，请检查输入');
  }
  return date.getTime() - 8 * 60 * 60 * 1000;
}

export function formatCampusDate(timestamp: number): string {
  const date = new Date(timestamp + 8 * 60 * 60 * 1000);
  return `${date.getUTCFullYear()}-${String(date.getUTCMonth() + 1).padStart(2, '0')}-${String(date.getUTCDate()).padStart(2, '0')} ${String(date.getUTCHours()).padStart(2, '0')}:${String(date.getUTCMinutes()).padStart(2, '0')}`;
}
