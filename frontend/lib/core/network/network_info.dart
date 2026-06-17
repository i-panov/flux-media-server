abstract class NetworkInfo {
  Future<bool> get isConnected;
}

class NetworkInfoImpl implements NetworkInfo {
  const NetworkInfoImpl();

  @override
  Future<bool> get isConnected async => true;
}
