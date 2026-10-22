namespace AhaKey.Integrations;

public static class IntegrationStartup
{
    // Inspection only; never installs, repairs or changes native hook trust.
    public static async Task<bool> InitializeAsync(IntegrationManager manager,bool optedIn,int port=HookContract.Port)
    {
        await manager.RefreshAsync();
        return optedIn && manager.Statuses.Any(s=>s.Ready) && manager.Server.Start(port);
    }
}
