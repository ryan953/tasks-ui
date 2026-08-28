import Foundation

/// The GraphQL documents the app sends.
///
/// Only the fields the UI shows are requested. Linear has far more depth; the app
/// links out to the website for the rest rather than trying to mirror it.
public enum LinearQueries {
    public static let issueFields = """
    id
    identifier
    title
    description
    priority
    url
    updatedAt
    state { id name type color }
    team { id key name }
    project { id name }
    assignee { name }
    """

    public static let viewer = """
    query Viewer {
      viewer { id name email }
      organization { urlKey name }
    }
    """

    public static let myIssues = """
    query MyIssues($filter: IssueFilter!, $after: String) {
      issues(first: 100, after: $after, filter: $filter, orderBy: updatedAt) {
        pageInfo { hasNextPage endCursor }
        nodes { \(issueFields) }
      }
    }
    """

    public static let myProjects = """
    query MyProjects($filter: ProjectFilter!) {
      projects(first: 100, filter: $filter, orderBy: updatedAt) {
        nodes {
          id
          name
          description
          url
          progress
          targetDate
          updatedAt
          status { id name type }
          lead { name }
        }
      }
    }
    """

    public static let teamStates = """
    query TeamStates($teamId: String!) {
      team(id: $teamId) {
        states { nodes { id name type color } }
      }
    }
    """

    public static let updateIssue = """
    mutation UpdateIssue($id: String!, $input: IssueUpdateInput!) {
      issueUpdate(id: $id, input: $input) {
        success
        issue { \(issueFields) }
      }
    }
    """

    /// Only name, description and target date are editable from the app; project
    /// status uses a per-workspace set that is better changed in Linear itself.
    public static let updateProject = """
    mutation UpdateProject($id: String!, $input: ProjectUpdateInput!) {
      projectUpdate(id: $id, input: $input) {
        success
        project {
          id
          name
          description
          url
          progress
          targetDate
          updatedAt
          status { id name type }
          lead { name }
        }
      }
    }
    """

    // MARK: - Filters

    /// Issues assigned to the authenticated user.
    public static func myIssuesFilter(includeDone: Bool) -> [String: Any] {
        var filter: [String: Any] = ["assignee": ["isMe": ["eq": true]]]
        if !includeDone {
            filter["state"] = ["type": ["nin": ["completed", "canceled"]]]
        }
        return filter
    }

    /// Projects the user leads or is a member of.
    public static var myProjectsFilter: [String: Any] {
        [
            "or": [
                ["lead": ["isMe": ["eq": true]]],
                ["members": ["some": ["isMe": ["eq": true]]]],
            ],
        ]
    }

    /// Narrower fallback, for a workspace where the member filter is rejected.
    public static var ledProjectsFilter: [String: Any] {
        ["lead": ["isMe": ["eq": true]]]
    }
}

/// Web links into Linear.
public enum LinearLinks {
    /// The workspace's own "my issues" view — the bulk list of everything assigned
    /// to the signed-in user.
    public static func myIssues(urlKey: String) -> URL? {
        URL(string: "https://linear.app/\(urlKey)/my-issues")
    }

    /// Everything the user created, as opposed to what they were assigned.
    public static func createdByMe(urlKey: String) -> URL? {
        URL(string: "https://linear.app/\(urlKey)/my-issues/created")
    }

    public static func projects(urlKey: String) -> URL? {
        URL(string: "https://linear.app/\(urlKey)/projects")
    }

    /// A search view pre-filled with a query.
    public static func search(urlKey: String, query: String) -> URL? {
        var components = URLComponents(string: "https://linear.app/\(urlKey)/search")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        return components?.url
    }
}
