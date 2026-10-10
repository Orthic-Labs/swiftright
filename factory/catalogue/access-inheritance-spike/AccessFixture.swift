public enum PublicFixture {
  case visible
}

internal enum InternalFixture {
  case hidden
}

private enum FilePrivateFixture {
  case hidden
}

public enum PublicParentFixture {
  public enum ExplicitPublicNested {
    case visible
  }

  internal enum ExplicitInternalNested {
    case hidden
  }

  private enum ExplicitPrivateNested {
    case hidden
  }

  enum DefaultNested {
    case hidden
  }
}
