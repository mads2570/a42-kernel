// SPDX-License-Identifier: GPL-2.0
/*
 *  linux/fs/attr.c
 *
 *  Copyright (C) 1991, 1992  Linus Torvalds
 *  changes by Thomas Schoebel-Theuer
 */

#include <linux/export.h>
#include <linux/time.h>
#include <linux/mm.h>
#include <linux/string.h>
#include <linux/sched/signal.h>
#include <linux/capability.h>
#include <linux/fsnotify.h>
#include <linux/fcntl.h>
#include <linux/security.h>
#include <linux/evm.h>
#include <linux/ima.h>
#include <linux/task_integrity.h>

static bool chown_ok(const struct inode *inode, kuid_t uid)
{
	if (uid_eq(current_fsuid(), inode->i_uid) &&
	    uid_eq(uid, inode->i_uid))
		return true;
	if (capable_wrt_inode_uidgid(inode, CAP_CHOWN))
		return true;
	if (uid_eq(inode->i_uid, INVALID_UID) &&
	    ns_capable(inode->i_sb->s_user_ns, CAP_CHOWN))
		return true;
	return false;
}

static bool chgrp_ok(const struct inode *inode, kgid_t gid)
{
	if (uid_eq(current_fsuid(), inode->i_uid) &&
	    (in_group_p(gid) || gid_eq(gid, inode->i_gid)))
		return true;
	if (capable_wrt_inode_uidgid(inode, CAP_CHOWN))
		return true;
	if (gid_eq(inode->i_gid, INVALID_GID) &&
	    ns_capable(inode->i_sb->s_user_ns, CAP_CHOWN))
		return true;
	return false;
}

/**
 * setattr_prepare - check if attribute changes to a dentry are allowed
 * @dentry:	dentry to check
 * @attr:	attributes to change
 *
 * Check if we are allowed to change the attributes contained in @attr
 * in the given dentry.  This includes the normal unix access permission
 * checks, as well as checks for rlimits and others. The function also clears
 * SGID bit from mode if user is not allowed to set it. Also file capabilities
 * and IMA extended attributes are cleared if ATTR_KILL_PRIV is set.
 *
 * Should be called as the first thing in ->setattr implementations,
 * possibly after taking additional locks.
 */
int setattr_prepare(struct dentry *dentry, struct iattr *attr)
{
	struct inode *inode = d_inode(dentry);
	unsigned int ia_valid = attr->ia_valid;

	/*
	 * First check size constraints.  These can't be overriden using
	 * ATTR_FORCE.
	 */
	if (ia_valid & ATTR_SIZE) {
		int error = inode_newsize_ok(inode, attr->ia_size);
		if (error)
			return error;
	}

	/* If force is set do it anyway. */
	if (ia_valid & ATTR_FORCE)
		goto kill_priv;

	/* Make sure a caller can chown. */
	if ((ia_valid & ATTR_UID) && !chown_ok(inode, attr->ia_uid))
		return -EPERM;

	/* Make sure caller can chgrp. */
	if ((ia_valid & ATTR_GID) && !chgrp_ok(inode, attr->ia_gid))
		return -EPERM;

	/* Make sure a caller can chmod. */
	if (ia_valid & ATTR_MODE) {
		if (!inode_owner_or_capable(inode))
			return -EPERM;
		/* Also check the setgid bit! */
		if (!in_group_p((ia_valid & ATTR_GID) ? attr->ia_gid :
				inode->i_gid) &&
		    !capable_wrt_inode_uidgid(inode, CAP_FSETID))
			attr->ia_mode &= ~S_ISGID;
	}

	/* Check for setting the inode time. */
	if (ia_valid & (ATTR_MTIME_SET | ATTR_ATIME_SET | ATTR_TIMES_SET)) {
		if (!inode_owner_or_capable(inode))
			return -EPERM;
	}

kill_priv:
	/* User has permission for the change */
	if (ia_valid & ATTR_KILL_PRIV) {
		int error;

		error = security_inode_killpriv(dentry);
		if (error)
			return error;
	}

	return 0;
}
EXPORT_SYMBOL(setattr_prepare);

/**
 * inode_newsize_ok - may this inode be truncated to a given size
 * @inode:	the inode to be truncated
 * @offset:	the new size to assign to the inode
 *
 * inode_newsize_ok must be called with i_mutex held.
 *
 * inode_newsize_ok will check filesystem limits and ulimits to check that the
 * new inode size is within limits. inode_newsize_ok will also send SIGXFSZ
 * when necessary. Caller must not proceed with inode size change if failure is
 * returned. @inode must be a file (not directory), with appropriate
 * permissions to allow truncate (inode_newsize_ok does NOT check these
 * conditions).
 *
 * Return: 0 on success, -ve errno on failure
 */
int inode_newsize_ok(const struct inode *inode, loff_t offset)
{
	if (offset < 0)
		return -EINVAL;
	if (inode->i_size < offset) {
		unsigned long limit;

		limit = rlimit(RLIMIT_FSIZE);
		if (limit != RLIM_INFINITY && offset > limit)
			goto out_sig;
		if (offset > inode->i_sb->s_maxbytes)
			goto out_big;
	} else {
		/*
		 * truncation of in-use swapfiles is disallowed - it would
		 * cause subsequent swapout to scribble on the now-freed
		 * blocks.
		 */
		if (IS_SWAPFILE(inode))
			return -ETXTBSY;
	}

	return 0;
out_sig:
	send_sig(SIGXFSZ, current, 0);
out_big:
	return -EFBIG;
}
EXPORT_SYMBOL(inode_newsize_ok);

/**
 * setattr_copy - copy simple metadata updates into the generic inode
 * @inode:	the inode to be updated
 * @attr:	the new attributes
 *
 * setattr_copy must be called with i_mutex held.
 *
 * setattr_copy updates the inode's metadata with that specified
 * in attr. Noticeably missing is inode size update, which is more complex
 * as it requires pagecache updates.
 *
 * The inode is not marked as dirty after this operation. The rationale is
 * that for "simple" filesystems, the struct inode is the inode storage.
 * The caller is free to mark the inode dirty afterwards if needed.
 */
void setattr_copy(struct inode *inode, const struct iattr *attr)
{
	unsigned int ia_valid = attr->ia_valid;

	if (ia_valid & ATTR_UID)
		inode->i_uid = attr->ia_uid;
	if (ia_valid & ATTR_GID)
		inode->i_gid = attr->ia_gid;
	if (ia_valid & ATTR_ATIME)
		inode->i_atime = timespec64_trunc(attr->ia_atime,
						  inode->i_sb->s_time_gran);
	if (ia_valid & ATTR_MTIME)
		inode->i_mtime = timespec64_trunc(attr->ia_mtime,
						  inode->i_sb->s_time_gran);
	if (ia_valid & ATTR_CTIME)
		inode->i_ctime = timespec64_trunc(attr->ia_ctime,
						  inode->i_sb->s_time_gran);
	if (ia_valid & ATTR_MODE) {
		umode_t mode = attr->ia_mode;

		if (!in_group_p(inode->i_gid) &&
		    !capable_wrt_inode_uidgid(inode, CAP_FSETID))
			mode &= ~S_ISGID;
		inode->i_mode = mode;
	}
}
EXPORT_SYMBOL(setattr_copy);

/**
 * notify_change - modify attributes of a filesytem object
 * @dentry:	object affected
 * @attr:	new attributes
 * @delegated_inode: returns inode, if the inode is delegated
 *
 * The caller must hold the i_mutex on the affected object.
 *
 * If notify_change discovers a delegation in need of breaking,
 * it will return -EWOULDBLOCK and return a reference to the inode in
 * delegated_inode.  The caller should then break the delegation and
 * retry.  Because breaking a delegation may take a long time, the
 * caller should drop the i_mutex before doing so.
 *
 * Alternatively, a caller may pass NULL for delegated_inode.  This may
 * be appropriate for callers that expect the underlying filesystem not
 * to be NFS exported.  Also, passing NULL is fine for callers holding
 * the file open for write, as there can be no conflicting delegation in
 * that case.
 */
int notify_change2(struct vfsmount *mnt, struct dentry * dentry, struct iattr * attr, struct inode **delegated_inode)
{
	struct inode *inode = dentry->d_inode;
	umode_t mode = inode->i_mode;
	int error;
	struct timespec64 now;
	unsigned int ia_valid = attr->ia_valid;

	WARN_ON_ONCE(!inode_is_locked(inode));

	if (ia_valid & (ATTR_MODE | ATTR_UID | ATTR_GID | ATTR_TIMES_SET)) {
		if (IS_IMMUTABLE(inode) || IS_APPEND(inode))
			return -EPERM;
	}

	/*
	 * If utimes(2) and friends are called with times == NULL (or both
	 * times are UTIME_NOW), then we need to check for write permission
	 */
	if (ia_valid & ATTR_TOUCH) {
		if (IS_IMMUTABLE(inode))
			return -EPERM;

		if (!inode_owner_or_capable(inode)) {
			error = inode_permission2(mnt, inode, MAY_WRITE);
			if (error)
				return error;
		}
	}

	if ((ia_valid & ATTR_MODE)) {
		umode_t amode = attr->ia_mode;
		/* Flag setting protected by i_mutex */
		if (is_sxid(amode))
			inode->i_flags &= ~S_NOSEC;
	}

	now = current_time(inode);

	attr->ia_ctime = now;
	if (!(ia_valid & ATTR_ATIME_SET))
		attr->ia_atime = now;
	if (!(ia_valid & ATTR_MTIME_SET))
		attr->ia_mtime = now;
	if (ia_valid & ATTR_KILL_PRIV) {
		error = security_inode_need_killpriv(dentry);
		if (error < 0)
			return error;
		if (error == 0)
			ia_valid = attr->ia_valid &= ~ATTR_KILL_PRIV;
	}

	/*
	 * We now pass ATTR_KILL_S*ID to the lower level setattr function so
	 * that the function has the ability to reinterpret a mode change
	 * that's due to these bits. This adds an implicit restriction that
	 * no function will ever call notify_change with both ATTR_MODE and
	 * ATTR_KILL_S*ID set.
	 */
	if ((ia_valid & (ATTR_KILL_SUID|ATTR_KILL_SGID)) &&
	    (ia_valid & ATTR_MODE))
		BUG();

	if (ia_valid & ATTR_KILL_SUID) {
		if (mode & S_ISUID) {
			ia_valid = attr->ia_valid |= ATTR_MODE;
			attr->ia_mode = (inode->i_mode & ~S_ISUID);
		}
	}
	if (ia_valid & ATTR_KILL_SGID) {
		if ((mode & (S_ISGID | S_IXGRP)) == (S_ISGID | S_IXGRP)) {
			if (!(ia_valid & ATTR_MODE)) {
				ia_valid = attr->ia_valid |= ATTR_MODE;
				attr->ia_mode = inode->i_mode;
			}
			attr->ia_mode &= ~S_ISGID;
		}
	}
	if (!(attr->ia_valid & ~(ATTR_KILL_SUID | ATTR_KILL_SGID)))
		return 0;

	/*
	 * Verify that uid/gid changes are valid in the target
	 * namespace of the superblock.
	 */
	if (ia_valid & ATTR_UID &&
	    !kuid_has_mapping(inode->i_sb->s_user_ns, attr->ia_uid))
		return -EOVERFLOW;
	if (ia_valid & ATTR_GID &&
	    !kgid_has_mapping(inode->i_sb->s_user_ns, attr->ia_gid))
		return -EOVERFLOW;

	/* Don't allow modifications of files with invalid uids or
	 * gids unless those uids & gids are being made valid.
	 */
	if (!(ia_valid & ATTR_UID) && !uid_valid(inode->i_uid))
		return -EOVERFLOW;
	if (!(ia_valid & ATTR_GID) && !gid_valid(inode->i_gid))
		return -EOVERFLOW;

	error = security_inode_setattr(dentry, attr);
	if (error)
		return error;
	error = try_break_deleg(inode, delegated_inode);
	if (error)
		return error;

	if (mnt && inode->i_op->setattr2)
		error = inode->i_op->setattr2(mnt, dentry, attr);
	else if (inode->i_op->setattr)
		error = inode->i_op->setattr(dentry, attr);
	else
		error = simple_setattr(dentry, attr);

	if (!error) {
		fsnotify_change(dentry, ia_valid);
		five_inode_post_setattr(current, dentry);
		ima_inode_post_setattr(dentry);
		evm_inode_post_setattr(dentry, ia_valid);
	}

	return error;
}
EXPORT_SYMBOL_GPL(notify_change2);

int notify_change(struct dentry * dentry, struct iattr * attr, struct inode **delegated_inode)
{
	return notify_change2(NULL, dentry, attr, delegated_inode);
}
EXPORT_SYMBOL(notify_change);
