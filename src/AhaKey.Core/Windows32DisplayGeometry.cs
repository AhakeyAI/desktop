namespace AhaKey.Core;

// eternal-dev bc4f6e4: four fixed profile allocations, Default/Working/WaitingError/Completed.
public sealed record DisplayAllocation(HardwareProfileId Profile, DisplayState State, int StartSlot, int Capacity)
{
    public int StartAddress => checked(StartSlot * Windows32DisplayGeometry.Stride);
    public int EndAddressExclusive => checked((StartSlot + Capacity) * Windows32DisplayGeometry.Stride);
    public int FirstSector => StartAddress / 4096;
    public int EndSectorExclusive => EndAddressExclusive / 4096;
    public bool Contains(int address, int length) => length > 0 && address >= StartAddress && (long)address + length <= EndAddressExclusive;
}
public static class Windows32DisplayGeometry
{
    public const int Stride = 28672;
    public const int FlashBytes = 8 * 1024 * 1024;
    public static int Capacity(DisplayState state) => state switch
    { DisplayState.Default => 8, DisplayState.Working or DisplayState.WaitingError or DisplayState.Completed => 12, _ => throw new ArgumentOutOfRangeException(nameof(state)) };
    public static DisplayAllocation Target(HardwareProfileId profile, DisplayState state)
    {
        if (!Enum.IsDefined(profile)) throw new ArgumentOutOfRangeException(nameof(profile));
        int offset = state switch { DisplayState.Default => 0, DisplayState.Working => 8, DisplayState.WaitingError => 20, DisplayState.Completed => 32, _ => throw new ArgumentOutOfRangeException(nameof(state)) };
        return new(profile, state, (int)profile * 44 + offset, Capacity(state));
    }
}
