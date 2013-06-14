---
layout: architect
title: Acess control
---

Acess control
=============

Role concept
------------

-   User: Login with user name and password
-   Group: Users can belong to one or multiple groups
-   Role: User and/or groups have roles.
-   Permissions: Permissions for certain resources (e.g. topics, WMS services) are assigned to roles

Special users and roles: A special user named 'admin' with all permissions is added automatically. For each site a role with the same name is defining the permissions for a public user not logged in.

Example:

-   This role has the following permissions
-   User 'lieni' is member of group 'forest_editors'
-   This group has role 'forest_edit'

Permission:

    Layer +show ForestMap/*
    Tool +show ForestMap/EditTool
    Topic +edit ForestMap
    Layer +edit ForestMap/Forest


Self organized groups
---------------------

Signup workflow:

-   User receives invitation mail with signup link
-   Sign up of users
-   Group administrator receives a mail with direct link for activating users


Administration page with links to all topics with self-administration: http://localhost:3000/groups_users

Signup link example for a user: http://localhost:3000/session/sign_up?group=forest_editors

Preparation:

-   Create roles. E.g. exampleedit, exampleview and exampleadmin
    Assign one ore more users the exampleadmin role
-   Create groups. E.G. examplegroupedit and examplegroupview
    Assign roles to groups: examplegroupedit -> exampleedit, examplegroupview -> exampleview
-   If you add users manually to groups, don't forget to mark the membership 'granted' flag
-   Assign permissions to the roles. E.g. exampleedit is allowed to edit a the example topic
-   Set permission for action 'edit' of resource type 'Group' for admin role. E.g. role exampleadmin for group examplegroupedit und examplegroupview

Extend registration forms with group specific fields:

-   Add a partial _app_infos.html.erb with specific fields in directory app/views/registrationsGROUPNAME 
-   Add a group specific mail test in _app/views/groups_users/mails/_GROUPNAME.html.erb

Send signup URL for groups to invited users.